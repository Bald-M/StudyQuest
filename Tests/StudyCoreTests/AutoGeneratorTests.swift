import Foundation
import Testing
@testable import StudyCore

private func shanghai() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return c
}

private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

private func makeStore(clock: FixedClock) throws -> StudyStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
    return try StudyStore(database: AppDatabase(url: dir.appendingPathComponent("test.sqlite")), clock: clock, notifier: NoopChangeNotifier())
}

private func problem(_ prompt: String) -> ProblemInput {
    ProblemInput(stageIndex: 0, moduleKey: nil, kind: .shortAnswer, prompt: prompt, options: nil,
                 referenceAnswer: "答案", rubric: "评分标准", maxScore: 10, difficulty: .medium, tags: nil)
}

/// 记录调用、真的往库里写作业和周测的假生成服务；可让下一次调用抛错。
private final class FakeGenerator: ContentGenerating, @unchecked Sendable {
    struct Failure: Error, LocalizedError { var errorDescription: String? { "模型超时" } }

    let store: StudyStore
    private let lock = NSLock()
    private var _assignmentModules: [Int64] = []
    private var _quizCalls = 0
    private var _failures = 0

    init(store: StudyStore) { self.store = store }

    var assignmentModules: [Int64] { lock.withLock { _assignmentModules } }
    var quizCalls: Int { lock.withLock { _quizCalls } }
    func failNext(_ count: Int) { lock.withLock { _failures = count } }

    private func shouldFail() -> Bool {
        lock.withLock {
            guard _failures > 0 else { return false }
            _failures -= 1
            return true
        }
    }

    func generateAssignment(moduleId: Int64, size: Int) async throws -> Int64 {
        lock.withLock { _assignmentModules.append(moduleId) }
        await Task.yield()
        if shouldFail() { throw Failure() }
        let module = try store.module(id: moduleId)
        return try store.createAssignment(
            AssignmentInput(stageIndex: module.stageIndex, moduleKey: module.key, title: "作业 \(module.key)", problemIds: nil,
                            problems: [problem("题 \(module.key)")]),
            source: "test")
    }

    func generateWeeklyQuiz() async throws -> Int64 {
        lock.withLock { _quizCalls += 1 }
        await Task.yield()
        if shouldFail() { throw Failure() }
        let section = SectionInput(title: "综合", weight: 100, source: .problems, problemIds: nil, problems: [problem("周测题")])
        // 与 GenerationService 一致：生成的周测是草稿（草稿也算本周已有周测）
        return try store.createExam(ExamInput(stageIndex: 0, kind: .weeklyQuiz, title: "周测", timeLimitMinutes: 30, sections: [section]),
                                    source: "test", status: .draft).id
    }
}

private struct Fixture {
    let clock: FixedClock
    let store: StudyStore
    let fake: FakeGenerator
    let auto: AutoGenerator

    init(start: String = "2026-11-25T04:00:00Z", learning: Int = 2, configured: Bool = true) throws {
        clock = FixedClock(date(start), calendar: shanghai())
        store = try makeStore(clock: clock)
        fake = FakeGenerator(store: store)
        let configuredFlag = configured
        auto = AutoGenerator(store: store, generation: fake, isConfigured: { configuredFlag })
        let modules = try store.stages().flatMap { try store.modules(stage: $0.index) }
        for module in modules.prefix(learning) {
            clock.current.addTimeInterval(1)  // startedAt 严格递增，保证顺序
            try store.setModuleStatus(id: module.id!, .learning)
        }
        clock.current = date(start)
    }
}

@Suite struct AutoGeneratorTests {
    @Test func claimIsExclusivePerDay() async throws {
        let f = try Fixture(learning: 4)
        async let a = f.auto.runIfNeeded()
        async let b = f.auto.runIfNeeded()
        let results = await [a, b]
        #expect(results.contains(.done))
        #expect(results.allSatisfy { $0 == .done || $0 == .running })
        #expect(f.fake.assignmentModules.count == 3)
        #expect(Set(f.fake.assignmentModules).count == 3)
        #expect(try f.store.assignments(day: f.clock.today()).count == 3)
        #expect(try f.store.autoGenRun(day: f.clock.today())?.status == "done")
    }

    @Test func capsAtDailyMax() async throws {
        let f = try Fixture(learning: 5)
        #expect(await f.auto.runIfNeeded() == .done)
        #expect(f.fake.assignmentModules.count == 3)
        let learning = try f.store.learningModules().compactMap(\.id)
        #expect(f.fake.assignmentModules == Array(learning.prefix(3)))
    }

    @Test func disabledDoesNothing() async throws {
        let f = try Fixture()
        try f.store.setSetting(.autoGenEnabled, "false")
        #expect(await f.auto.runIfNeeded() == .disabled)
        #expect(try f.store.autoGenRun(day: f.clock.today()) == nil)
        #expect(f.fake.assignmentModules.isEmpty)
    }

    @Test func skipsModulesWithAssignmentToday() async throws {
        let f = try Fixture(learning: 2)
        let first = try #require(try f.store.learningModules().first?.id)
        _ = try await f.fake.generateAssignment(moduleId: first, size: 5)
        #expect(await f.auto.runIfNeeded() == .done)
        #expect(f.fake.assignmentModules.count == 2)  // 手动 1 次 + 自动补另一个模块
        #expect(!f.fake.assignmentModules.dropFirst().contains(first))
    }

    @Test func sundayAddsWeeklyQuizOnce() async throws {
        let f = try Fixture(start: "2026-11-29T04:00:00Z", learning: 1)  // 周日 12:00（上海）
        #expect(await f.auto.runIfNeeded() == .done)
        #expect(try f.store.exams(stage: nil).filter { $0.kind == .weeklyQuiz }.count == 1)

        #expect(await f.auto.runIfNeeded() == .done)  // 同一天不再 claim
        #expect(f.fake.quizCalls == 1)
        #expect(try f.store.exams(stage: nil).filter { $0.kind == .weeklyQuiz }.count == 1)

        f.clock.current = date("2026-12-06T04:00:00Z")  // 下一个周日
        #expect(await f.auto.runIfNeeded() == .done)
        #expect(try f.store.exams(stage: nil).filter { $0.kind == .weeklyQuiz }.count == 2)
    }

    @Test func weekdayDoesNotGenerateQuiz() async throws {
        let f = try Fixture(learning: 1)  // 周三
        #expect(await f.auto.runIfNeeded() == .done)
        #expect(f.fake.quizCalls == 0)
    }

    @Test func notConfiguredDoesNotClaim() async throws {
        let f = try Fixture(configured: false)
        #expect(await f.auto.runIfNeeded() == .notConfigured)
        #expect(try f.store.autoGenRun(day: f.clock.today()) == nil)
        #expect(f.fake.assignmentModules.isEmpty)
    }

    @Test func failureRecordedAndRetryable() async throws {
        let f = try Fixture(learning: 1)
        f.fake.failNext(1)
        guard case .failed(let errors) = await f.auto.runIfNeeded() else {
            Issue.record("应为 failed")
            return
        }
        #expect(errors.count == 1 && errors[0].contains("模型超时"))
        let run = try #require(try f.store.autoGenRun(day: f.clock.today()))
        #expect(run.status == "failed" && run.errors == errors)
        // 当天不会自动反复重试
        guard case .failed = await f.auto.runIfNeeded() else {
            Issue.record("同日再次运行应仍为 failed")
            return
        }
        #expect(f.fake.assignmentModules.count == 1)

        #expect(await f.auto.retry() == .done)
        #expect(f.fake.assignmentModules.count == 2)
        #expect(try f.store.autoGenRun(day: f.clock.today())?.status == "done")
        #expect(try f.store.autoGenRun(day: f.clock.today())?.errors == [])
        #expect(try f.store.assignments(day: f.clock.today()).count == 1)
    }

    @Test func retryDoesNotExceedDailyMax() async throws {
        let f = try Fixture(learning: 5)
        f.fake.failNext(1)  // 第一份失败，另外两份成功
        guard case .failed = await f.auto.runIfNeeded() else {
            Issue.record("应为 failed")
            return
        }
        #expect(try f.store.assignments(day: f.clock.today()).count == 2)
        #expect(await f.auto.retry() == .done)
        #expect(try f.store.assignments(day: f.clock.today()).count == 3)
    }

    @Test func newDayTriggersAutoGenerationOnce() async throws {
        let f = try Fixture(start: "2026-11-25T15:59:00Z", learning: 1)  // 11-25 23:59（上海）
        #expect(f.clock.today().rawValue == "2026-11-25")
        #expect(await f.auto.runIfNeeded() == .done)
        #expect(f.fake.assignmentModules.count == 1)

        f.clock.current = date("2026-11-25T16:01:00Z")  // 11-26 00:01
        #expect(f.clock.today().rawValue == "2026-11-26")
        #expect(await f.auto.runIfNeeded() == .done)
        #expect(f.fake.assignmentModules.count == 2)

        #expect(await f.auto.runIfNeeded() == .done)
        #expect(f.fake.assignmentModules.count == 2)
    }
}
