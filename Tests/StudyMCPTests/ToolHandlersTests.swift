import Foundation
import StudyCore
import Testing
@testable import StudyMCP

private let uniqueAnswer = "REF-独一无二-7f3a9"

private func makeHandlers() throws -> (ToolHandlers, StudyStore) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-mcp-test-\(UUID().uuidString)")
    let store = try StudyStore(database: AppDatabase(url: dir.appendingPathComponent("test.sqlite")),
                               clock: SystemClock(), notifier: NoopChangeNotifier())
    return (ToolHandlers(store: store, clientName: { "claude-code" }), store)
}

private func problemJSON(prompt: String, answer: String = uniqueAnswer) -> JSONValue {
    .object([
        "stage_index": .number(0), "kind": .string("shortAnswer"), "prompt": .string(prompt),
        "reference_answer": .string(answer), "rubric": .string("评分要点"), "max_score": .number(10),
        "difficulty": .string("medium"),
    ])
}

private func examArgs(weights: [Double]) -> [String: JSONValue] {
    let sections = weights.enumerated().map { i, w in
        JSONValue.object(["title": .string("分区 \(i)"), "weight": .number(w), "problems": .array([problemJSON(prompt: "题 \(i)")])])
    }
    return ["exam": .object([
        "stage_index": .number(0), "kind": .string("weeklyQuiz"), "title": .string("周测"),
        "time_limit_minutes": .number(30), "sections": .array(sections),
    ])]
}

private func object(_ result: ToolResult) throws -> [String: JSONValue] {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(result.text.utf8))
    guard case .object(let dict) = value else { throw StoreError.invalid("不是对象：\(result.text)") }
    return dict
}

private func int(_ value: JSONValue?) -> Int64? {
    if case .number(let n) = value { return Int64(n) }
    return nil
}

@Suite struct ToolHandlersTests {
    @Test func createExamThenGetHidesAnswers() throws {
        let (handlers, store) = try makeHandlers()
        let created = handlers.call(name: "create_exam", arguments: examArgs(weights: [40, 60]))
        #expect(!created.isError, "\(created.text)")
        let examId = try #require(int(try object(created)["exam_id"]))

        let exam = handlers.call(name: "get_exam", arguments: ["exam_id": .number(Double(examId))])
        #expect(!exam.isError, "\(exam.text)")
        #expect(exam.text.contains("题 0"))
        #expect(!exam.text.contains(uniqueAnswer))

        let attempt = try store.startExam(id: examId)
        #expect(!handlers.call(name: "get_exam", arguments: ["exam_id": .number(Double(examId))]).text.contains(uniqueAnswer))
        try store.submit(attemptId: attempt.id!)
        #expect(handlers.call(name: "get_exam", arguments: ["exam_id": .number(Double(examId))]).text.contains(uniqueAnswer))
    }

    @Test func missingArgumentNamedInSnakeCase() throws {
        let (handlers, _) = try makeHandlers()
        let result = handlers.call(name: "get_stage", arguments: [:])
        #expect(result.isError)
        #expect(result.text.contains("stage_index"))
    }

    @Test func createExamValidationError() throws {
        let (handlers, _) = try makeHandlers()
        let result = handlers.call(name: "create_exam", arguments: examArgs(weights: [40, 50]))
        #expect(result.isError)
        #expect(result.text.contains("权重"))
    }

    @Test func submitGradingFinalizes() throws {
        let (handlers, store) = try makeHandlers()
        let created = handlers.call(name: "create_assignment", arguments: ["assignment": .object([
            "stage_index": .number(0), "title": .string("MCP 作业"),
            "problems": .array([problemJSON(prompt: "一"), problemJSON(prompt: "二")]),
        ])])
        #expect(!created.isError, "\(created.text)")
        let assignmentId = try #require(int(try object(created)["assignment_id"]))

        let attempt = try store.startAssignment(id: assignmentId)
        let attemptId = try #require(attempt.id)
        let problemIds = try store.attemptDetail(id: attemptId).items.map { $0.problem.id! }
        #expect(try store.problems(ids: problemIds).allSatisfy { $0.source == "mcp:claude-code" })
        for id in problemIds { try store.saveAnswer(attemptId: attemptId, problemId: id, answer: "我的答案") }
        try store.submit(attemptId: attemptId)

        let detail = handlers.call(name: "get_attempt", arguments: ["attempt_id": .number(Double(attemptId))])
        #expect(!detail.isError, "\(detail.text)")
        #expect(detail.text.contains(uniqueAnswer))

        let grades = problemIds.map {
            JSONValue.object(["problem_id": .number(Double($0)), "score": .number(8), "feedback": .string("不错"),
                              "mistakes": .array([.string("细节")])])
        }
        let graded = handlers.call(name: "submit_grading", arguments: ["attempt_id": .number(Double(attemptId)), "grades": .array(grades)])
        #expect(!graded.isError, "\(graded.text)")

        let after = try store.attemptDetail(id: attemptId)
        #expect(after.attempt.status == .graded)
        #expect(after.items.allSatisfy { $0.grades.last?.grader == "mcp:claude-code" })
        #expect(after.items.allSatisfy { $0.grades.last?.raw.contains("\"feedback\"") == true })
    }

    @Test func submitGradingRejectsInProgress() throws {
        let (handlers, store) = try makeHandlers()
        let id = try store.createAssignment(
            AssignmentInput(stageIndex: 0, moduleKey: nil, title: "作业", problemIds: nil,
                            problems: [ProblemInput(stageIndex: 0, moduleKey: nil, kind: .shortAnswer, prompt: "一", options: nil,
                                                    referenceAnswer: "答", rubric: "标", maxScore: 10, difficulty: .easy, tags: nil)]),
            source: "test")
        let attempt = try store.startAssignment(id: id)
        let problemId = try #require(try store.attemptDetail(id: attempt.id!).items.first?.problem.id)
        let result = handlers.call(name: "submit_grading", arguments: [
            "attempt_id": .number(Double(attempt.id!)),
            "grades": .array([.object(["problem_id": .number(Double(problemId)), "score": .number(5), "feedback": .string("x")])]),
        ])
        #expect(result.isError)
        #expect(try store.attemptDetail(id: attempt.id!).items.allSatisfy { $0.grades.isEmpty })
    }

    @Test func unknownToolIsError() throws {
        let (handlers, _) = try makeHandlers()
        #expect(handlers.call(name: "nope", arguments: [:]).isError)
    }

    @Test func notFoundIsErrorNotCrash() throws {
        let (handlers, _) = try makeHandlers()
        let result = handlers.call(name: "get_exam", arguments: ["exam_id": .number(999)])
        #expect(result.isError)
        #expect(result.text.contains("未找到"))
    }

    @Test func toolCatalogMatchesHandlers() throws {
        let expected: Set<String> = [
            "get_progress", "get_today", "list_stages", "get_stage", "create_cards", "create_problems",
            "create_assignment", "create_exam", "list_exams", "get_exam", "list_attempts", "get_attempt",
            "submit_grading", "list_mistakes", "update_stage_settings",
        ]
        #expect(Set(ToolCatalog.tools.map(\.name)) == expected)
        #expect(ToolCatalog.tools.count == 15)
        let (handlers, _) = try makeHandlers()
        for name in ["get_progress", "get_today", "list_stages", "list_exams", "list_attempts", "list_mistakes"] {
            let result = handlers.call(name: name, arguments: [:])
            #expect(!result.isError, "\(name): \(result.text)")
        }
    }

    @Test func promptsRenderWithStageData() throws {
        let (_, store) = try makeHandlers()
        #expect(Set(PromptCatalog.prompts.map(\.name)) == ["generate_stage_exam", "generate_weekly_quiz", "analyze_weakness"])
        let stage = try store.stage(2)
        let text = try PromptCatalog.render(name: "generate_stage_exam", arguments: ["stage_index": .string("2")], store: store)
        #expect(text.contains(stage.title))
        #expect(text.contains("create_exam"))
        for name in ["generate_weekly_quiz", "analyze_weakness"] {
            #expect(!(try PromptCatalog.render(name: name, arguments: [:], store: store)).isEmpty)
        }
    }
}
