import AppKit
import Foundation
import Observation
import StudyCore

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case today, map, review, mistakes, practice, exams, growth, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今日"
        case .map: "地图"
        case .review: "复习"
        case .mistakes: "错题本"
        case .practice: "练习与作业"
        case .exams: "考试"
        case .growth: "成长"
        case .settings: "设置"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .map: "map"
        case .review: "rectangle.on.rectangle"
        case .mistakes: "exclamationmark.bubble"
        case .practice: "square.and.pencil"
        case .exams: "doc.text"
        case .growth: "chart.line.uptrend.xyaxis"
        case .settings: "gearshape"
        }
    }
}

/// 整个 App 的状态：持有 store 与各服务，负责刷新今日与进度、启动/回到前台时的例行工作。
@MainActor @Observable final class AppModel {
    let store: StudyStore
    let database: AppDatabase
    let dbURL: URL
    let registry: ProviderRegistry

    var selection: SidebarItem = .today
    var today: TodaySummary?
    var progress: ProgressSummary?
    var loadError: String?
    /// 启动时恢复备份失败的说明；界面顶部显示，用户可关闭。
    var restoreError: String?
    /// 每次 refresh 加一；页面据此重读自己的数据。
    var revision = 0

    /// 最近一次自动生成的结果；当天有数据库记录时以记录为准。
    private var lastAutoGen: AutoGenStatus = .done
    private var launchInFlight = false
    /// AppModel 与 App 同生命周期，只需持有观察者令牌。
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    @ObservationIgnored lazy var grading = GradingService(store: store, model: { [registry] in try registry.model(for: .grading) })
    @ObservationIgnored lazy var generation = GenerationService(store: store, model: { [registry] in try registry.model(for: .generation) })
    @ObservationIgnored lazy var tutor = TutorService(store: store, model: { [registry] in try registry.model(for: .generation) })
    @ObservationIgnored lazy var autoGenerator = AutoGenerator(
        store: store, generation: generation, isConfigured: { [registry] in registry.isConfigured(.generation) })

    /// 解析数据库路径（`STUDYQUEST_DB_PATH` 优先），先应用待恢复的备份，再打开数据库。
    static func open() throws -> AppModel {
        let url = try ProcessInfo.processInfo.environment["STUDYQUEST_DB_PATH"].map { URL(fileURLWithPath: $0) }
            ?? AppDatabase.defaultURL()
        var restoreError: String?
        do {
            try BackupService.applyPendingRestore(at: url)
        } catch BackupError.pendingRestoreInvalid(let reason) {
            restoreError = reason
        } catch {
            restoreError = "从备份恢复失败，继续使用现有数据：\(error)"
        }
        let database = try AppDatabase(url: url)
        let store = try StudyStore(database: database, clock: SystemClock(), notifier: DistributedChangeNotifier())
        let model = AppModel(store: store, database: database, dbURL: url)
        model.restoreError = restoreError
        return model
    }

    init(store: StudyStore, database: AppDatabase, dbURL: URL) {
        self.store = store
        self.database = database
        self.dbURL = dbURL
        self.registry = ProviderRegistry(store: store, secrets: KeychainStore(), http: URLSessionHTTPClient())
        subscribe()
        refresh()
    }

    func refresh() {
        do {
            let autoGen = try store.autoGenRun(day: store.clock.today()).map(AutoGenerator.status(of:)) ?? lastAutoGen
            let summary = try TodayBuilder.build(store: store, autoGen: autoGen)
            today = summary
            progress = summary.progress
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        revision += 1
    }

    /// 过期作答 → 每日自动生成 → 补判已交卷但还有待判题的作答 → 刷新。同一时间只跑一轮。
    func onLaunchOrForeground() async {
        guard !launchInFlight else { return }
        launchInFlight = true
        defer { launchInFlight = false }

        do {
            _ = try store.expireOverdueAttempts()
        } catch {
            loadError = error.localizedDescription
        }
        refresh()
        lastAutoGen = await autoGenerator.runIfNeeded()
        if registry.isConfigured(.grading) {
            let submitted = (try? store.attempts(examId: nil, status: .submitted)) ?? []
            for attempt in submitted {
                guard let id = attempt.id, !((try? store.pendingGrading(attemptId: id)) ?? []).isEmpty else { continue }
                _ = await grading.grade(attemptId: id)
            }
        }
        refresh()
    }

    private func subscribe() {
        let dataChanged = DistributedNotificationCenter.default().addObserver(forName: DistributedChangeNotifier.name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let active = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.onLaunchOrForeground() }
        }
        observers = [dataChanged, active]
    }
}
