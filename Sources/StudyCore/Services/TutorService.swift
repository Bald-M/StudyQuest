import Foundation

/// 助教：按阶段给提示，以及模拟面试的对话与评分。
public final class TutorService {
    private let store: StudyStore
    private let model: () throws -> ChatModel

    public init(store: StudyStore, model: @escaping () throws -> ChatModel) {
        self.store = store
        self.model = model
    }

    // MARK: 提示

    public func hint(problemId: Int64, currentAnswer: String) async throws -> String {
        guard let problem = try store.problems(ids: [problemId]).first else { throw StoreError.notFound("题目 \(problemId)") }
        var lines = ["题型：\(problem.kind.rawValue)", "题干：\(problem.prompt)"]
        if !problem.options.isEmpty { lines.append("选项：\n" + problem.options.joined(separator: "\n")) }
        lines.append("学生目前的答案：\(currentAnswer.isEmpty ? "（还没写）" : currentAnswer)")
        let request = ChatRequest(system: Self.hintSystem(stage: problem.stageIndex),
                                  messages: [ChatMessage(role: "user", content: lines.joined(separator: "\n"))])
        return try await model().complete(request)
    }

    static func hintSystem(stage: Int) -> String {
        let base = "你是耐心的编程助教，用中文回答，简短清楚。"
        return stage <= 3
            ? base + "学生还在打基础：只给思路和提示，不给完整答案或完整代码；可以指出方向、提醒相关概念、追问学生的想法。"
            : base + "学生已有基础：可以直接指出问题所在，并给出具体的做法或示例代码。"
    }

    // MARK: 模拟面试

    private static let interviewSystem = """
        你是严格而友善的技术面试官，正在面试一位自学编程的候选人。用中文，每次只问一个问题或做一次简短追问；\
        根据候选人的回答逐步加深，覆盖基础知识、项目经验与解决问题的思路。不要替候选人回答，也不要在面试过程中打分。
        """

    private static let scoringSystem = """
        你是技术面试的评分官。根据面试记录按评分表打分：技术准确性 40 分、思路与深度 30 分、表达清晰度 20 分、应变与诚实 10 分，\
        合计 0 到 100。feedback 写总评，指出优点与最需要改进的地方。只输出符合 schema 的 JSON，不要任何其他文字。
        """

    private struct InterviewScore: Decodable {
        var score: Double
        var feedback: String
    }

    private static let scoreSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object(["score": .object(["type": .string("number")]), "feedback": .object(["type": .string("string")])]),
        "required": .array([.string("score"), .string("feedback")]),
        "additionalProperties": .bool(false),
    ])

    public func interviewReply(interviewId: Int64?, userMessage: String) async throws -> (interviewId: Int64, reply: String) {
        var interview: MockInterview
        if let interviewId {
            guard let existing = try store.mockInterview(id: interviewId) else { throw StoreError.notFound("面试 \(interviewId)") }
            interview = existing
        } else {
            interview = MockInterview(transcript: [], createdAt: store.clock.now())
        }
        interview.transcript.append(ChatTurn(role: "user", content: userMessage))
        let reply = try await model().complete(ChatRequest(
            system: Self.interviewSystem, messages: interview.transcript.map { ChatMessage(role: $0.role, content: $0.content) }))
        interview.transcript.append(ChatTurn(role: "assistant", content: reply))
        let saved = try store.saveMockInterview(interview)
        return (saved.id!, reply)
    }

    public func finishInterview(id: Int64) async throws -> MockInterview {
        guard var interview = try store.mockInterview(id: id) else { throw StoreError.notFound("面试 \(id)") }
        guard interview.transcript.contains(where: { $0.role == "user" }) else { throw StoreError.invalid("面试还没有开始，无法打分") }
        let transcript = interview.transcript.map { ($0.role == "user" ? "候选人：" : "面试官：") + $0.content }.joined(separator: "\n")
        let chat = try model()
        let raw = try await chat.complete(ChatRequest(
            system: Self.scoringSystem, messages: [ChatMessage(role: "user", content: "面试记录：\n" + transcript)], jsonSchema: Self.scoreSchema))
        let result = try JSONReply.decode(InterviewScore.self, from: raw)
        interview.score = min(max(result.score, 0), 100)
        interview.feedback = result.feedback
        interview.grader = chat.label
        return try store.saveMockInterview(interview)
    }
}
