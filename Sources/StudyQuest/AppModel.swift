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
    /// 各作答最近一次判卷失败的原因（已转成给人看的说明）；判卷成功或没有失败时清除。
    var gradingFailures: [Int64: String] = [:]
    /// 每次 refresh 加一；页面据此重读自己的数据。
    var revision = 0
    /// 出处链接要跳到的节（教材 id → 节 id）；该教材的阅读器窗口读到后清除。
    var pendingReaderSection: [Int64: Int64] = [:]

    /// 最近一次自动生成的结果；当天有数据库记录时以记录为准。
    private var lastAutoGen: AutoGenStatus = .done
    private var launchInFlight = false
    /// 正在判卷的作答：交卷判卷、手动重新判卷、复判与回前台补判共用，同一作答同一时间只判一次。
    /// 需要被观察：结果页据此显示「正在判卷」，否则撞上后台补判时点重新判卷会没有任何反应。
    private var gradingInFlight: Set<Int64> = []
    /// 本次启动中回前台已自动补判过的作答：每个作答每次启动最多自动补判一次，失败的留给手动重新判卷。
    @ObservationIgnored private var autoGradedThisLaunch: Set<Int64> = []
    /// AppModel 与 App 同生命周期，只需持有观察者令牌。
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    @ObservationIgnored lazy var grading = GradingService(store: store, model: { [registry] in try registry.model(for: .grading) })
    @ObservationIgnored lazy var generation = GenerationService(store: store, model: { [registry] in try registry.model(for: .generation) })
    @ObservationIgnored lazy var tutor = TutorService(store: store, model: { [registry] in try registry.model(for: .generation) })
    @ObservationIgnored lazy var sectionChallenges = SectionChallengeService(store: store, model: { [registry] in try registry.model(for: .generation) })
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
        } catch BackupError.recoveredOriginal(let reason) {
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
                guard let id = attempt.id, !autoGradedThisLaunch.contains(id),
                      !((try? store.pendingGrading(attemptId: id)) ?? []).isEmpty else { continue }
                autoGradedThisLaunch.insert(id)
                _ = await gradeExclusively(attemptId: id)
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

    /// 题目或卡片的教材出处；没有 sectionId 或读取失败时为 nil。
    func origin(sectionId: Int64?) -> SectionOrigin? {
        sectionId.flatMap { try? store.origin(sectionId: $0) }
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
        _ = await gradeExclusively(attemptId: attemptId)
        refresh()
    }

    /// 该作答已在判卷时直接返回 nil，不重复发请求；判完记下第一处失败的原因。
    private func gradeExclusively(attemptId: Int64) async -> GradingReport? {
        guard gradingInFlight.insert(attemptId).inserted else { return nil }
        defer { gradingInFlight.remove(attemptId) }
        let report = await grading.grade(attemptId: attemptId)
        gradingFailures[attemptId] = report.firstError.map(userMessage)
        return report
    }

    func isGrading(attemptId: Int64) -> Bool { gradingInFlight.contains(attemptId) }

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
        /// 各模块挂上的章节掌握数（模块 id → 已掌握 / 总数）。
        var sectionCounts: [Int64: (mastered: Int, total: Int)]
    }

    func stageDetail(_ index: Int) throws -> StageDetail {
        let gate = try store.stageGateStatus(stage: index)  // 会同步 needsRelearn，须先于读模块
        let exams = try store.exams(stage: index).filter { $0.kind == .stageExam }
            .reversed().map { StageExamRow(exam: $0, attempts: try store.attempts(examId: $0.id, status: nil)) }
        let modules = try store.modules(stage: index)
        var sectionCounts: [Int64: (mastered: Int, total: Int)] = [:]
        for id in modules.compactMap(\.id) { sectionCounts[id] = try store.masteredCount(moduleId: id) }
        return StageDetail(stage: try store.stage(index), modules: modules, gate: gate, exams: exams, sectionCounts: sectionCounts)
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

    // MARK: 教材

    func textbookRows(stage: Int?) throws -> [TextbookSummary] { try store.textbookSummaries(stage: stage) }

    func modules(stage: Int) throws -> [Module] { try store.modules(stage: stage) }

    /// 文件夹按 Markdown 文件夹读，`.pdf` 按 pdf，`.md`/`.markdown` 按单个 Markdown 文件。
    nonisolated static func sourceKind(of url: URL) throws -> TextbookSourceKind {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return .markdownFolder }
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "md", "markdown": return .markdownFile
        default: throw StoreError.invalid("只支持 .md、.pdf 文件或 Markdown 文件夹")
        }
    }

    nonisolated static func readTextbook(at url: URL, kind: TextbookSourceKind) throws -> ParsedTextbook {
        switch kind {
        case .markdownFile: try MarkdownTextbookReader.read(file: url)
        case .markdownFolder: try MarkdownTextbookReader.read(folder: url)
        case .pdf: try PDFTextbookReader.read(file: url)
        }
    }

    /// 在后台线程解析，避免大 pdf 卡住界面。
    func parseTextbook(at url: URL) async throws -> ParsedTextbook {
        try await Task.detached { try Self.readTextbook(at: url, kind: try Self.sourceKind(of: url)) }.value
    }

    /// 写入可能有几十 MB 的 pdf，放到后台线程。
    func importTextbook(_ parsed: ParsedTextbook, stage: Int, sourcePath: String) async throws -> Int64 {
        let store = store
        let id = try await Task.detached { try store.importTextbook(parsed, stageIndex: stage, sourcePath: sourcePath) }.value
        refresh()
        return id
    }

    func sectionRows(textbookId: Int64) async throws -> [SectionRow] {
        let store = store
        return try await Task.detached { try store.sectionRows(textbookId: textbookId) }.value
    }

    func suggestModules(textbookId: Int64) async throws -> [Int64: String?] {
        try await sectionChallenges.suggestModules(textbookId: textbookId)
    }

    func saveModuleMapping(_ mapping: [Int64: Int64?]) throws {
        try store.setSectionModules(mapping)
        refresh()
    }

    /// 按教材原来的类型重新解析 `url`（默认是导入时的路径）并比对；路径不存在时抛 `StoreError.notFound("原文件")`。
    func syncPreview(textbook: TextbookSummary, from url: URL? = nil) async throws -> (SyncPlan, ParsedTextbook) {
        let source = url ?? URL(fileURLWithPath: textbook.sourcePath)
        let store = store, id = textbook.id, kind = textbook.sourceKind
        return try await Task.detached {
            guard FileManager.default.fileExists(atPath: source.path) else { throw StoreError.notFound("原文件") }
            let parsed = try Self.readTextbook(at: source, kind: kind)
            return (try store.syncPreview(textbookId: id, parsed: parsed), parsed)
        }.value
    }

    /// `sourcePath` 为重新选择的原文件位置；nil 表示沿用原路径。
    func applySync(textbookId: Int64, parsed: ParsedTextbook, sourcePath: String? = nil) async throws {
        let store = store
        try await Task.detached { try store.applySync(textbookId: textbookId, parsed: parsed, sourcePath: sourcePath) }.value
        refresh()
    }

    func deleteTextbook(id: Int64) throws {
        try store.deleteTextbook(id: id)
        refresh()
    }

    // MARK: 阅读器与章节闯关

    /// 阅读器一次读取的内容：教材（不含 pdf 数据）、可见的节与阶段是否锁定。教材不存在或已删除时 `textbook` 为 nil。
    struct ReaderSnapshot: Sendable {
        var textbook: Textbook?
        var rows: [SectionRow]
        var stageLocked: Bool
        var assetRefs: Set<String>
    }

    /// 大教材的正文可能很多，在后台线程读。
    func readerSnapshot(textbookId: Int64) async throws -> ReaderSnapshot {
        let store = store
        return try await Task.detached {
            guard let book = try store.textbook(id: textbookId), book.deletedAt == nil else {
                return ReaderSnapshot(textbook: nil, rows: [], stageLocked: false, assetRefs: [])
            }
            return ReaderSnapshot(
                textbook: book, rows: try store.sectionRows(textbookId: textbookId),
                stageLocked: try store.stage(book.stageIndex).status == .locked,
                assetRefs: book.sourceKind == .pdf ? [] : Set(try store.assetRefs(textbookId: textbookId)))
        }.value
    }

    func pdfData(textbookId: Int64) async throws -> Data? {
        let store = store
        return try await Task.detached { try store.pdfData(textbookId: textbookId) }.value
    }

    func setLastRead(textbookId: Int64, sectionId: Int64) {
        try? store.setLastRead(textbookId: textbookId, sectionId: sectionId)
    }

    /// 阶段锁定时直接拒绝，不调用 AI；否则取（或生成）本节闯关并开始作答。
    func prepareSectionChallenge(sectionId: Int64) async throws -> (attemptId: Int64, truncated: Bool) {
        let section = try store.section(id: sectionId)
        if let book = try store.textbook(id: section.textbookId), try store.stage(book.stageIndex).status == .locked {
            throw StoreError.blocked(Self.stageLockedMessage)
        }
        let prepared = try await sectionChallenges.prepareChallenge(sectionId: sectionId)
        let attempt = try store.startSectionChallenge(challengeId: prepared.challengeId)
        refresh()
        return (attempt.id!, prepared.truncated)
    }

    /// 与 `startSectionChallenge` 拒绝时的说明一致。
    static let stageLockedMessage = "该阶段尚未解锁，可以先阅读，解锁后再闯关"

    /// 章节闯关结果页的一句话。
    enum SectionOutcome: Equatable {
        case mastered
        case failed(passLine: Double)
        case practice
    }

    /// 本节在这次作答开始前已掌握即为练习模式；否则过关即本次掌握，未过关给出过关线。
    func sectionOutcome(attempt: Attempt) throws -> SectionOutcome? {
        guard attempt.kind == .section, let passed = attempt.passed, let challengeId = attempt.sectionChallengeId,
              let section = try store.section(challengeId: challengeId) else { return nil }
        if let masteredAt = section.masteredAt, masteredAt < attempt.startedAt { return .practice }
        if passed { return .mastered }
        guard let book = try store.textbook(id: section.textbookId) else { return nil }
        return .failed(passLine: try store.stage(book.stageIndex).passLine)
    }

    // MARK: 考试与结果

    /// 考试页一个阶段的分组：该阶段的全部试卷、当前门槛与模块（门槛原因需要模块名）。
    struct ExamGroup: Identifiable {
        var stage: Stage
        var modules: [Module]
        var gate: StageGateStatus
        var rows: [StageExamRow]
        var id: Int { stage.index }
    }

    func examGroups() throws -> [ExamGroup] {
        try store.stages().compactMap { stage in
            let exams = try store.exams(stage: stage.index).reversed()
            guard !exams.isEmpty else { return nil }
            let gate = try store.stageGateStatus(stage: stage.index)  // 先于读模块：会同步 needsRelearn
            let rows = try exams.map { StageExamRow(exam: $0, attempts: try store.attempts(examId: $0.id, status: nil)) }
            return ExamGroup(stage: stage, modules: try store.modules(stage: stage.index), gate: gate, rows: rows)
        }
    }

    /// 开考；已有作答则继续或查看，不会开第二次。先处理过期作答，过期的会直接显示成绩。
    func openExam(id: Int64) throws {
        _ = try store.expireOverdueAttempts()
        if let existing = try store.attempts(examId: id, status: nil).first {
            activeAttemptId = existing.id
        } else {
            activeAttemptId = try store.startExam(id: id).id
        }
        refresh()
    }

    func confirmExam(id: Int64) throws {
        try store.confirmExam(id: id)
        refresh()
    }

    func discardExam(id: Int64) throws {
        try store.discardExam(id: id)
        refresh()
    }

    func now() -> Date { store.clock.now() }

    /// 结果页要用的试卷、阶段，以及未通过时的冷却状态。
    struct ResultContext {
        var exam: Exam?
        var stage: Stage?
        var gate: StageGateStatus?
    }

    func resultContext(attempt: Attempt) throws -> ResultContext {
        guard attempt.kind == .exam, let examId = attempt.examId, let exam = try store.exams(stage: nil).first(where: { $0.id == examId }) else {
            return ResultContext()
        }
        let stage = try store.stage(exam.stageIndex)
        let gate = exam.kind == .stageExam && attempt.passed == false ? try store.stageGateStatus(stage: exam.stageIndex) : nil
        return ResultContext(exam: exam, stage: stage, gate: gate)
    }

    func regrade(attemptId: Int64, problemId: Int64) async throws {
        guard gradingInFlight.insert(attemptId).inserted else { throw StoreError.blocked("这份作答正在判卷，请稍后再试") }
        defer {
            gradingInFlight.remove(attemptId)
            refresh()
        }
        try await grading.regrade(attemptId: attemptId, problemId: problemId)
    }

    func hasSeenReward(attemptId: Int64) -> Bool { (try? store.hasSeenReward(attemptId: attemptId)) ?? true }

    func markRewardSeen(attemptId: Int64) { try? store.markRewardSeen(attemptId: attemptId) }

    func saveReflection(attemptId: Int64, text: String) throws {
        try store.saveReflection(attemptId: attemptId, text: text)
    }

    // MARK: 模拟面试

    func mockInterviews() throws -> [MockInterview] { try store.mockInterviews() }

    func mockInterview(id: Int64) throws -> MockInterview? { try store.mockInterview(id: id) }

    func interviewReply(interviewId: Int64?, message: String) async throws -> Int64 {
        defer { refresh() }
        return try await tutor.interviewReply(interviewId: interviewId, userMessage: message).interviewId
    }

    func finishInterview(id: Int64) async throws -> MockInterview {
        defer { refresh() }
        return try await tutor.finishInterview(id: id)
    }

    // MARK: 成长

    struct ExamScore: Identifiable {
        var id: Int64
        var title: String
        var gradedAt: Date
        var percent: Double
        var passed: Bool?
    }

    /// 已判卷考试的得分，按判卷时间升序。
    func examScores() throws -> [ExamScore] {
        let titles = Dictionary(uniqueKeysWithValues: try store.exams(stage: nil).compactMap { e in e.id.map { ($0, e.title) } })
        return try store.attempts(examId: nil, status: .graded).compactMap { attempt in
            guard attempt.kind == .exam, let id = attempt.id, let at = attempt.gradedAt, let percent = attempt.totalPercent else { return nil }
            return ExamScore(id: id, title: attempt.examId.flatMap { titles[$0] } ?? "考试", gradedAt: at, percent: percent, passed: attempt.passed)
        }.sorted { $0.gradedAt < $1.gradedAt }
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
