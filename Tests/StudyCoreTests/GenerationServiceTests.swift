import Foundation
import Testing
@testable import StudyCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func makeStore(clock: FixedClock = FixedClock(t0)) throws -> StudyStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
    return try StudyStore(database: AppDatabase(url: dir.appendingPathComponent("test.sqlite")), clock: clock, notifier: NoopChangeNotifier())
}

private func problemJSON(_ prompt: String, stage: Int = 0, module: String? = "s0.git") -> String {
    let key = module.map { "\"\($0)\"" } ?? "null"
    return """
        {"stageIndex": \(stage), "moduleKey": \(key), "kind": "shortAnswer", "prompt": "\(prompt)", "referenceAnswer": "参考", \
        "rubric": "评分", "maxScore": 10, "difficulty": "easy"}
        """
}

private func problemsReply(_ prompts: [String], module: String? = "s0.git") -> String {
    #"{"title": "练习", "problems": [\#(prompts.map { problemJSON($0, module: module) }.joined(separator: ","))]}"#
}

@Suite struct GenerationServiceTests {
    @Test func assignmentIsStoredWithModule() async throws {
        let store = try makeStore()
        let module = try #require(try store.module(key: "s0.git"))
        let model = FakeModel([.text(problemsReply((1...5).map { "题目\($0)" }))])
        let id = try await GenerationService(store: store, model: { model }).generateAssignment(moduleId: module.id!, size: 5)
        let assignment = try #require(try store.openAssignments().first { $0.id == id })
        #expect(assignment.moduleId == module.id)
        #expect(assignment.problemIds.count == 5)
        #expect(assignment.source == "app_ai")
        #expect(try store.problems(ids: assignment.problemIds).allSatisfy { $0.source == "app_ai" })
        let request = model.requests[0]
        #expect(request.jsonSchema != nil)
        #expect(request.messages[0].content.contains("Git"))
        #expect(request.messages[0].content.contains("简单"))
    }

    @Test func invalidOutputGetsOneFixAttempt() async throws {
        let store = try makeStore()
        let module = try #require(try store.module(key: "s0.git"))
        let model = FakeModel([.text(problemsReply(["", "好题"])), .text(problemsReply(["好题一", "好题二"]))])
        let id = try await GenerationService(store: store, model: { model }).generateAssignment(moduleId: module.id!, size: 2)
        #expect(model.calls == 2)
        let last = try #require(model.requests[1].messages.last)
        #expect(last.role == "user" && last.content.contains("题干"))
        #expect(model.requests[1].messages.count == 3)
        #expect(try store.openAssignments().contains { $0.id == id })
    }

    @Test func stillInvalidAfterFixThrows() async throws {
        let store = try makeStore()
        let module = try #require(try store.module(key: "s0.git"))
        let model = FakeModel([.text("不是 JSON"), .text(problemsReply([""]))])
        await #expect(throws: StoreError.self) {
            _ = try await GenerationService(store: store, model: { model }).generateAssignment(moduleId: module.id!, size: 1)
        }
        #expect(model.calls == 2)
        #expect(try store.openAssignments().isEmpty)
    }

    @Test func hintPolicyByStage() async throws {
        let store = try makeStore()
        func problem(stage: Int) throws -> Int64 {
            try store.createProblems([ProblemInput(stageIndex: stage, moduleKey: nil, kind: .shortAnswer, prompt: "解释 X", options: nil,
                                                   referenceAnswer: "答", rubric: "", maxScore: 10, difficulty: .easy, tags: nil)],
                                     source: "test")[0]
        }
        let early = FakeModel([.text("想想看")])
        let hint = try await TutorService(store: store, model: { early }).hint(problemId: try problem(stage: 2), currentAnswer: "我的草稿")
        #expect(hint == "想想看")
        #expect(early.requests[0].system.contains("不给完整答案"))
        #expect(early.requests[0].messages.last?.content.contains("我的草稿") == true)
        let late = FakeModel([.text("可以这样")])
        _ = try await TutorService(store: store, model: { late }).hint(problemId: try problem(stage: 5), currentAnswer: "")
        #expect(!late.requests[0].system.contains("不给完整答案"))
    }

    @Test func weeklyQuizMixesModules() async throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let terminal = try #require(try store.module(key: "s0.terminal"))
        let git = try #require(try store.module(key: "s0.git"))
        try store.setModuleStatus(id: terminal.id!, .done)
        clock.current = t0.addingTimeInterval(10 * 24 * 3600)
        try store.setModuleStatus(id: git.id!, .learning)
        let quiz = #"{"title": "本周测验", "problems": [\#(problemJSON("题一")), \#(problemJSON("题二", module: "s0.terminal"))]}"#
        let model = FakeModel([.text(quiz)])
        let id = try await GenerationService(store: store, model: { model }).generateWeeklyQuiz()
        let prompt = model.requests[0].messages[0].content
        #expect(prompt.contains(git.title) && prompt.contains(terminal.title))
        #expect(prompt.contains("80%") && prompt.contains("20%"))
        let detail = try store.examDetail(id: id, revealAnswers: true)
        #expect(detail.exam.kind == .weeklyQuiz && detail.exam.stageIndex == 0 && detail.exam.timeLimitMinutes == 30)
        #expect(detail.sections.count == 1 && detail.sections[0].section.title == "周测" && detail.sections[0].section.weight == 100)
        #expect(detail.exam.source == "app_ai")
    }

    @Test func stageExamIncludesAppendixFormat() async throws {
        let store = try makeStore()
        let stage = try store.stage(0)
        let body = #"{"title": "阶段 0 考试", "timeLimitMinutes": 90, "sections": [{"title": "上机", "weight": 100, "problems": [\#(problemJSON("做一次合并"))]}]}"#
        let model = FakeModel([.text(body)])
        let result = try await GenerationService(store: store, model: { model }).generateStageExam(stage: 0)
        #expect(try store.exams(stage: 0).contains { $0.id == result.id })
        #expect(model.requests[0].messages[0].content.contains(stage.summary))
        #expect(model.requests[0].messages[0].content.contains("20%") && model.requests[0].messages[0].content.contains("30%"))
    }

    @Test func cardsAreStoredForModule() async throws {
        let store = try makeStore()
        let module = try #require(try store.module(key: "s0.git"))
        let body = #"{"cards": [{"stageIndex": 0, "front": "git add", "back": "暂存"}, {"stageIndex": 0, "front": "git commit", "back": "提交"}]}"#
        let ids = try await GenerationService(store: store, model: { FakeModel([.text(body)]) }).generateCards(moduleId: module.id!, count: 2)
        #expect(ids.count == 2)
    }

    @Test func finishInterviewStoresScore() async throws {
        let store = try makeStore()
        let model = FakeModel([.text("请先自我介绍"), .text("说说闭包"), .text("```json\n{\"score\": 82, \"feedback\": \"表达清晰\"}\n```")])
        let tutor = TutorService(store: store, model: { model })
        let first = try await tutor.interviewReply(interviewId: nil, userMessage: "开始")
        #expect(first.reply == "请先自我介绍")
        let second = try await tutor.interviewReply(interviewId: first.interviewId, userMessage: "我是学生")
        #expect(second.interviewId == first.interviewId)
        let saved = try #require(try store.mockInterview(id: first.interviewId))
        #expect(saved.transcript.map(\.role) == ["user", "assistant", "user", "assistant"])
        #expect(model.requests[1].messages.count == 3)
        let done = try await tutor.finishInterview(id: first.interviewId)
        #expect(done.score == 82 && done.feedback == "表达清晰" && done.grader == "fake:test")
        #expect(try store.mockInterview(id: first.interviewId)?.score == 82)
    }

    @Test func interviewScoreIsClamped() async throws {
        let store = try makeStore()
        let model = FakeModel([.text("你好"), .text(#"{"score": 140, "feedback": "好"}"#)])
        let tutor = TutorService(store: store, model: { model })
        let turn = try await tutor.interviewReply(interviewId: nil, userMessage: "hi")
        #expect(try await tutor.finishInterview(id: turn.interviewId).score == 100)
    }
}
