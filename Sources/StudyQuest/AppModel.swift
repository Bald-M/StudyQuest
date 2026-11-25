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
    /// 今日页点进作业/考试时带过去的 id；练习与考试页（后续任务）据此定位。
    var selectedAssignmentId: Int64?
    var selectedExamId: Int64?
    /// 错题重做创建的作答；Task 16 的 AnswerView 据此打开。
    var activeAttemptId: Int64?
    /// 本 App 发起的自动生成重试正在进行。
    var retryingAutoGen = false
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

    // MARK: 今日、复习、错题（视图只经由这里访问数据库）

    func retryAutoGen() async {
        guard !retryingAutoGen else { return }
        retryingAutoGen = true
        defer { retryingAutoGen = false }
        lastAutoGen = await autoGenerator.retry()
        refresh()
    }

    func reviewQueue() throws -> (cards: [Card], deferred: Int) { try store.reviewQueue() }

    func recordReview(cardId: Int64, remembered: Bool) throws {
        try store.recordReview(cardId: cardId, remembered: remembered)
        refresh()
    }

    func reviewClearedToday() throws -> Bool {
        try store.hasXP(reason: .reviewCleared, on: store.clock.today())
    }

    func dailyNoteText() throws -> String {
        try store.dailyNote(day: store.clock.today())?.text ?? ""
    }

    func saveDailyNote(_ text: String) throws {
        try store.saveDailyNote(text)
        refresh()
    }

    /// 错题本一行：错题、原题、最近一次已判卷重做的得分。
    struct MistakeRow: Identifiable {
        var mistake: Mistake
        var problem: Problem?
        var lastPercent: Double?
        var id: Int64 { mistake.id ?? 0 }
    }

    func mistakeRows() throws -> [MistakeRow] {
        let mistakes = try store.mistakes(includeGraduated: false)
        let problems = Dictionary(uniqueKeysWithValues: try store.problems(ids: mistakes.map(\.problemId)).compactMap { p in p.id.map { ($0, p) } })
        var lastPercent: [Int64: Double] = [:]
        for attempt in try store.attempts(examId: nil, status: .graded) {
            // 按开始时间倒序，每道错题取第一条
            if let id = attempt.mistakeId, lastPercent[id] == nil, let percent = attempt.totalPercent { lastPercent[id] = percent }
        }
        return mistakes.map { MistakeRow(mistake: $0, problem: problems[$0.problemId], lastPercent: lastPercent[$0.id ?? 0]) }
    }

    /// 已有未判完的重做则继续它，否则新开一次。
    func startMistakeRedo(mistakeId: Int64) throws {
        if let open = try store.openRedoAttempt(mistakeId: mistakeId) {
            activeAttemptId = open.id
            return
        }
        let attempt = try store.startMistakeRedo(mistakeId: mistakeId)
        activeAttemptId = attempt.id
        refresh()
    }

    // MARK: 练习与作业

    /// 练习页一行：作业与它最近一次已判卷的得分。
    struct AssignmentRow: Identifiable {
        var assignment: Assignment
        var lastPercent: Double?
        var id: Int64 { assignment.id ?? 0 }
    }

    /// 未完成的在前（日期倒序），已完成的在后。
    func assignmentRows() throws -> (open: [AssignmentRow], completed: [AssignmentRow]) {
        var lastPercent: [Int64: Double] = [:]
        for attempt in try store.attempts(examId: nil, status: .graded) {
            if let id = attempt.assignmentId, lastPercent[id] == nil, let percent = attempt.totalPercent { lastPercent[id] = percent }
        }
        let rows = { (list: [Assignment]) in list.map { AssignmentRow(assignment: $0, lastPercent: lastPercent[$0.id ?? 0]) } }
        return (rows(try store.openAssignments().reversed()), rows(try store.completedAssignments()))
    }

    /// 打开作业：有未判完的作答就继续，否则有已判卷的就看结果，都没有则新开一次。
    func openAssignment(id: Int64) throws {
        let attempts = try store.attempts(assignmentId: id)
        if let existing = attempts.first(where: { $0.status != .graded }) ?? attempts.first {
            activeAttemptId = existing.id
        } else {
            activeAttemptId = try store.startAssignment(id: id).id
            refresh()
        }
    }

    // MARK: 作答

    func attemptDetail(id: Int64) throws -> AttemptDetail { try store.attemptDetail(id: id) }

    func saveAnswer(attemptId: Int64, problemId: Int64, answer: String) throws {
        try store.saveAnswer(attemptId: attemptId, problemId: problemId, answer: answer)
    }

    /// 交卷并判卷；判卷从不抛错，失败的题保持待判。
    func submitAndGrade(attemptId: Int64) async throws {
        // 自动保存撞上截止时间时已被自动交卷，这里不再重复交
        if try store.attemptDetail(id: attemptId).attempt.status == .inProgress {
            try store.submit(attemptId: attemptId)
        }
        refresh()
        await regrade(attemptId: attemptId)
    }

    func regrade(attemptId: Int64) async {
        _ = await grading.grade(attemptId: attemptId)
        refresh()
    }

    func pendingGradingCount(attemptId: Int64) throws -> Int { try store.pendingGrading(attemptId: attemptId).count }

    func hint(problemId: Int64, currentAnswer: String) async throws -> String {
        try await tutor.hint(problemId: problemId, currentAnswer: currentAnswer)
    }

    // MARK: 地图与阶段详情

    func stages() throws -> [Stage] { try store.stages() }

    struct StageExamRow: Identifiable {
        var exam: Exam
        var attempts: [Attempt]
        var id: Int64 { exam.id ?? 0 }
    }

    struct StageDetail {
        var stage: Stage
        var modules: [Module]
        var gate: StageGateStatus
        var exams: [StageExamRow]
    }

    func stageDetail(_ index: Int) throws -> StageDetail {
        let gate = try store.stageGateStatus(stage: index)  // 会同步 needsRelearn，须先于读模块
        let exams = try store.exams(stage: index).filter { $0.kind == .stageExam }
            .reversed().map { StageExamRow(exam: $0, attempts: try store.attempts(examId: $0.id, status: nil)) }
        return StageDetail(stage: try store.stage(index), modules: try store.modules(stage: index), gate: gate, exams: exams)
    }

    func setModuleStatus(id: Int64, _ status: ModuleStatus) throws {
        try store.setModuleStatus(id: id, status)
        refresh()
    }

    func generateAssignment(moduleId: Int64) async throws {
        _ = try await generation.generateAssignment(moduleId: moduleId, size: 5)
        refresh()
    }

    func generateCards(moduleId: Int64) async throws {
        _ = try await generation.generateCards(moduleId: moduleId, count: 10)
        refresh()
    }

    func generateStageExam(stage: Int) async throws {
        _ = try await generation.generateStageExam(stage: stage)
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
