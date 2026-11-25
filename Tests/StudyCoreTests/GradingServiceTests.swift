import Foundation
import Testing
@testable import StudyCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func makeStore() throws -> StudyStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
    return try StudyStore(database: AppDatabase(url: dir.appendingPathComponent("test.sqlite")), clock: FixedClock(t0),
                          notifier: NoopChangeNotifier())
}

/// 按队列依次返回文本或抛错；记录每次请求。
private final class FakeModel: ChatModel, @unchecked Sendable {
    enum Reply { case text(String), error(Error) }
    private let lock = NSLock()
    private var queue: [Reply]
    private var recorded: [ChatRequest] = []
    init(_ replies: [Reply]) { queue = replies }
    var label: String { "fake:test" }
    var calls: Int { lock.withLock { recorded.count } }
    var requests: [ChatRequest] { lock.withLock { recorded } }
    func complete(_ request: ChatRequest) async throws -> String {
        let reply: Reply = lock.withLock {
            recorded.append(request)
            return queue.isEmpty ? .error(AIError.emptyResponse) : queue.removeFirst()
        }
        switch reply {
        case .text(let s): return s
        case .error(let e): throw e
        }
    }
}

private let good = #"{"score": 8, "feedback": "好", "mistakes": ["漏了一点"]}"#

/// 一个分区两道 10 分题的阶段 0 试卷，已开始并交卷（第一题有答案，第二题留空）。
private func submittedAttempt(_ store: StudyStore) throws -> (attemptId: Int64, problemIds: [Int64]) {
    func p(_ prompt: String) -> ProblemInput {
        ProblemInput(stageIndex: 0, moduleKey: "s0.git", kind: .shortAnswer, prompt: prompt, options: nil,
                     referenceAnswer: "参考答案", rubric: "评分标准", maxScore: 10, difficulty: .medium, tags: nil)
    }
    let section = SectionInput(title: "上机", weight: 100, source: .problems, problemIds: nil, problems: [p("题一"), p("题二")])
    let examId = try store.createExam(ExamInput(stageIndex: 0, kind: .stageExam, title: "考", timeLimitMinutes: 60, sections: [section]),
                                      source: "test").id
    let attempt = try store.startExam(id: examId)
    let ids = try store.attemptDetail(id: attempt.id!).items.map { $0.problem.id! }
    try store.saveAnswer(attemptId: attempt.id!, problemId: ids[0], answer: "我的答案")
    try store.submit(attemptId: attempt.id!)
    return (attempt.id!, ids)
}

@Suite struct GradingServiceTests {
    @Test func scoreIsClampedAndFencesStripped() async throws {
        let store = try makeStore()
        let (attemptId, _) = try submittedAttempt(store)
        let model = FakeModel([.text("```json\n{\"score\": 15, \"feedback\": \"好\", \"mistakes\": []}\n```"), .text(good)])
        let report = await GradingService(store: store, model: { model }).grade(attemptId: attemptId)
        #expect(report.graded == 2 && report.failed.isEmpty)
        let items = try store.attemptDetail(id: attemptId).items
        #expect(items[0].grades.last?.score == 10)
        #expect(items[0].grades.last?.grader == "fake:test")
        #expect(items[0].grades.last?.raw.hasPrefix("```json") == true)
        #expect(items[1].grades.last?.score == 8)
        // 请求内容：顺序、schema、系统提示、学生答案（含空答案）
        let requests = model.requests
        #expect(requests[0].jsonSchema == GradeResult.schema)
        #expect(requests[0].system.contains("rubric") || requests[0].system.contains("评分标准"))
        let first = requests[0].messages[0].content
        #expect(first.contains("题一") && first.contains("参考答案") && first.contains("评分标准") && first.contains("我的答案"))
        #expect(requests[1].messages[0].content.contains("题二"))
    }

    @Test func retriesThenSucceeds() async throws {
        let store = try makeStore()
        let (attemptId, _) = try submittedAttempt(store)
        let model = FakeModel([.text("not json"), .error(AIError.http(status: 500, body: "")), .text(good), .text(good)])
        let report = await GradingService(store: store, model: { model }).grade(attemptId: attemptId)
        #expect(report.graded == 2)
        #expect(report.failed.isEmpty)
        #expect(model.calls == 4)
    }

    @Test func failureLeavesPending() async throws {
        let store = try makeStore()
        let (attemptId, ids) = try submittedAttempt(store)
        let model = FakeModel([.text("x"), .text("{}"), .error(AIError.truncated), .text(good)])
        let report = await GradingService(store: store, model: { model }).grade(attemptId: attemptId)
        #expect(report.graded == 1)
        #expect(report.failed.count == 1 && report.failed[0].problemId == ids[0] && !report.failed[0].error.isEmpty)
        #expect(model.calls == 4)
        #expect(try store.attemptDetail(id: attemptId).attempt.status == .submitted)
        #expect(try store.pendingGrading(attemptId: attemptId).map(\.id) == [ids[0]])
    }

    @Test func modelFactoryFailureIsReported() async throws {
        let store = try makeStore()
        let (attemptId, ids) = try submittedAttempt(store)
        let service = GradingService(store: store, model: { throw AIError.notConfigured("provider") })
        let report = await service.grade(attemptId: attemptId)
        #expect(report.graded == 0 && report.failed.count == ids.count)
    }

    @Test func gradeOnUnsubmittedAttemptReportsFailure() async throws {
        let store = try makeStore()
        let report = await GradingService(store: store, model: { FakeModel([]) }).grade(attemptId: 999)
        #expect(report.graded == 0 && report.failed.count == 1 && report.failed[0].problemId == 0)
    }

    @Test func allGradedFinalizes() async throws {
        let store = try makeStore()
        let (attemptId, _) = try submittedAttempt(store)
        let model = FakeModel([.text(good), .text(good)])
        _ = await GradingService(store: store, model: { model }).grade(attemptId: attemptId)
        let attempt = try store.attemptDetail(id: attemptId).attempt
        #expect(attempt.status == .graded)
        #expect(attempt.totalPercent != nil)
    }

    @Test func regradeAddsRecord() async throws {
        let store = try makeStore()
        let (attemptId, ids) = try submittedAttempt(store)
        let service = GradingService(store: store, model: { FakeModel([.text(good), .text(good)]) })
        _ = await service.grade(attemptId: attemptId)
        let regrading = GradingService(store: store, model: {
            FakeModel([.text("bad"), .text(#"{"score": 3, "feedback": "复判", "mistakes": []}"#)])
        })
        try await regrading.regrade(attemptId: attemptId, problemId: ids[0])
        let item = try #require(try store.attemptDetail(id: attemptId).items.first)
        #expect(item.grades.count == 2)
        #expect(item.grades.last?.score == 3 && item.grades.last?.feedback == "复判")
    }

    @Test func regradeThrowsAfterThreeFailures() async throws {
        let store = try makeStore()
        let (attemptId, ids) = try submittedAttempt(store)
        let model = FakeModel([.text("a"), .text("b"), .text("c")])
        await #expect(throws: (any Error).self) {
            try await GradingService(store: store, model: { model }).regrade(attemptId: attemptId, problemId: ids[0])
        }
        #expect(model.calls == 3)
    }
}

@Suite struct GradeParserTests {
    @Test func parsesPlainFencedAndRejectsGarbage() throws {
        #expect(try GradeParser.parse(good) == GradeResult(score: 8, feedback: "好", mistakes: ["漏了一点"]))
        #expect(try GradeParser.parse("  ```\n\(good)\n```  ").score == 8)
        #expect(throws: AIError.self) { try GradeParser.parse("not json") }
        #expect(throws: AIError.self) { try GradeParser.parse(#"{"score": 1}"#) }
    }
}
