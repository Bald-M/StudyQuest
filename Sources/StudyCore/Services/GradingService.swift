import Foundation

public struct GradeResult: Codable, Equatable, Sendable {
    public var score: Double
    public var feedback: String
    public var mistakes: [String]

    public init(score: Double, feedback: String, mistakes: [String]) {
        self.score = score; self.feedback = feedback; self.mistakes = mistakes
    }

    public static let schema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "score": .object(["type": .string("number")]),
            "feedback": .object(["type": .string("string")]),
            "mistakes": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
        ]),
        "required": .array([.string("score"), .string("feedback"), .string("mistakes")]),
        "additionalProperties": .bool(false),
    ])
}

public enum GradeParser {
    /// 剥掉首尾的 ```json / ``` 围栏与空白后解码；失败抛 `AIError.invalidJSON`（带原文片段）。
    public static func parse(_ text: String) throws -> GradeResult {
        try JSONReply.decode(GradeResult.self, from: text)
    }
}

public struct GradingReport {
    public var graded: Int
    public var failed: [(problemId: Int64, error: String)]
}

public final class GradingService {
    private static let maxTries = 3
    private let store: StudyStore
    private let model: () throws -> ChatModel

    public init(store: StudyStore, model: @escaping () throws -> ChatModel) {
        self.store = store
        self.model = model
    }

    /// 逐题（按作答题序）判卷，从不抛错；失败的题保持无成绩。
    public func grade(attemptId: Int64) async -> GradingReport {
        var report = GradingReport(graded: 0, failed: [])
        let pending: [Problem]
        let answers: [Int64: String]
        do {
            pending = try store.pendingGrading(attemptId: attemptId)
            answers = try Self.answers(store.attemptDetail(id: attemptId))
        } catch {
            report.failed.append((0, "\(error)"))
            return report
        }
        guard !pending.isEmpty else { return report }
        let chat: ChatModel
        do { chat = try model() } catch {
            report.failed = pending.map { ($0.id!, "\(error)") }
            return report
        }
        for problem in pending {
            do {
                try await gradeOne(chat, attemptId: attemptId, problem: problem, answer: answers[problem.id!] ?? "")
                report.graded += 1
            } catch {
                report.failed.append((problem.id!, "\(error)"))
            }
        }
        return report
    }

    /// 对一道题重新判卷，新增一条记录（以最新为准）；重试 3 次仍失败则抛错。
    public func regrade(attemptId: Int64, problemId: Int64) async throws {
        let detail = try store.attemptDetail(id: attemptId)
        guard detail.attempt.status != .inProgress else { throw StoreError.invalid("作答尚未提交，不能判卷") }
        guard let item = detail.items.first(where: { $0.problem.id == problemId }) else {
            throw StoreError.invalid("题目 \(problemId) 不在这次作答中")
        }
        try await gradeOne(try model(), attemptId: attemptId, problem: item.problem, answer: item.answer ?? "")
    }

    private static func answers(_ detail: AttemptDetail) -> [Int64: String] {
        detail.items.reduce(into: [:]) { $0[$1.problem.id!] = $1.answer }
    }

    private func gradeOne(_ chat: ChatModel, attemptId: Int64, problem: Problem, answer: String) async throws {
        let request = ChatRequest(system: Self.systemPrompt, messages: [ChatMessage(role: "user", content: Self.userContent(problem, answer))],
                                  jsonSchema: GradeResult.schema)
        var lastError: Error = AIError.emptyResponse
        for _ in 0..<Self.maxTries {
            do {
                let raw = try await chat.complete(request)
                let result = try GradeParser.parse(raw)
                try store.recordGrade(attemptId: attemptId, problemId: problem.id!, score: result.score, feedback: result.feedback,
                                      mistakes: result.mistakes, grader: chat.label, raw: raw)
                return
            } catch let error as StoreError {
                throw error  // 存储失败重试无意义
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static let systemPrompt = """
        你是严格的判卷老师。严格按照评分标准（rubric）判分：score 取 0 到满分之间的数，feedback 简要说明得失，\
        mistakes 列出学生答错或遗漏的要点（全对则为空数组）。空答案按 0 分处理。只输出符合 schema 的 JSON，不要任何其他文字。
        """

    private static func userContent(_ p: Problem, _ answer: String) -> String {
        var lines = ["题型：\(p.kind.rawValue)", "题干：\(p.prompt)"]
        if !p.options.isEmpty { lines.append("选项：\n" + p.options.joined(separator: "\n")) }
        lines += ["参考答案：\(p.referenceAnswer)", "评分标准：\(p.rubric)", "满分：\(p.maxScore)",
                  "学生答案：\(answer.isEmpty ? "（空）" : answer)"]
        return lines.joined(separator: "\n")
    }
}
