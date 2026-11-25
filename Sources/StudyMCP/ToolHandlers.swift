import Foundation
import StudyCore

public struct ToolResult: Equatable, Sendable {
    /// 成功时为 JSON（snake_case 键），失败时为中文说明。
    public var text: String
    public var isError: Bool
}

/// 把 MCP 工具调用映射到 StudyStore。只处理 JSONValue，不依赖 MCP SDK。
public struct ToolHandlers {
    private let store: StudyStore
    private let clientName: () -> String

    public init(store: StudyStore, clientName: @escaping () -> String) {
        self.store = store
        self.clientName = clientName
    }

    public func call(name: String, arguments: [String: JSONValue]) -> ToolResult {
        do {
            return ToolResult(text: try dispatch(name: name, arguments: arguments), isError: false)
        } catch let error as StoreError {
            switch error {
            case .notFound(let what): return ToolResult(text: "未找到\(what)", isError: true)
            case .invalid(let message), .blocked(let message): return ToolResult(text: message, isError: true)
            }
        } catch let error as DecodingError {
            return ToolResult(text: Self.describe(error), isError: true)
        } catch {
            return ToolResult(text: "出错了：\(error.localizedDescription)", isError: true)
        }
    }

    private var mcpName: String { "mcp:\(clientName())" }

    private func dispatch(name: String, arguments: [String: JSONValue]) throws -> String {
        switch name {
        case "get_progress":
            return try progress()
        case "get_today":
            let autoGen = try store.autoGenRun(day: store.clock.today()).map(AutoGenerator.status(of:)) ?? .done
            return try encode(TodayOut(try TodayBuilder.build(store: store, autoGen: autoGen)))
        case "list_stages":
            return try encode(store.stages())
        case "get_stage":
            let args: StageArgs = try decode(arguments)
            return try encode(StageOut(stage: store.stage(args.stageIndex), modules: store.modules(stage: args.stageIndex)))
        case "create_cards":
            let args: CardsArgs = try decode(arguments)
            return try encode(["card_ids": store.createCards(args.cards, source: mcpName)])
        case "create_problems":
            let args: ProblemsArgs = try decode(arguments)
            return try encode(["problem_ids": store.createProblems(args.problems, source: mcpName)])
        case "create_assignment":
            let args: AssignmentArgs = try decode(arguments)
            return try encode(["assignment_id": store.createAssignment(args.assignment, source: mcpName)])
        case "create_exam":
            let args: ExamArgs = try decode(arguments)
            let result = try store.createExam(args.exam, source: mcpName)
            return try encode(CreatedExamOut(examId: result.id, warnings: result.warnings))
        case "list_exams":
            let args: OptionalStageArgs = try decode(arguments)
            return try encode(store.exams(stage: args.stageIndex))
        case "get_exam":
            let args: ExamIdArgs = try decode(arguments)
            // 判卷前（就绪、作答中）隐藏参考答案与评分标准。
            let hidden = try store.examDetail(id: args.examId, revealAnswers: false)
            let reveal = hidden.exam.status == .submitted || hidden.exam.status == .graded
            return try encode(reveal ? store.examDetail(id: args.examId, revealAnswers: true) : hidden)
        case "list_attempts":
            let args: AttemptsArgs = try decode(arguments)
            return try encode(store.attempts(examId: args.examId, status: args.status))
        case "get_attempt":
            let args: AttemptIdArgs = try decode(arguments)
            return try encode(AttemptOut(store.attemptDetail(id: args.attemptId)))
        case "submit_grading":
            return try submitGrading(arguments)
        case "list_mistakes":
            let args: MistakesArgs = try decode(arguments)
            let mistakes = try store.mistakes(includeGraduated: args.includeGraduated ?? false)
            // 同一道题毕业后再错会有多条错题，题目 id 可能重复
            let prompts = Dictionary(try store.problems(ids: mistakes.map(\.problemId)).map { ($0.id!, $0.prompt) },
                                     uniquingKeysWith: { first, _ in first })
            return try encode(mistakes.map { MistakeOut(mistake: $0, prompt: prompts[$0.problemId] ?? "") })
        case "update_stage_settings":
            let args: StageSettingsArgs = try decode(arguments)
            try store.updateStageSettings(index: args.stageIndex, passLine: args.passLine, cooldownDays: args.cooldownDays, reward: args.reward)
            return try encode(store.stage(args.stageIndex))
        default:
            throw StoreError.invalid("未知工具：\(name)")
        }
    }

    /// 进度摘要 + 进行中阶段的考试门槛（冷却、需重学）+ 需重学模块。门槛查询会同步 needsRelearn，所以先查门槛再取模块。
    private func progress() throws -> String {
        let stages = try store.stages()
        let gates = try stages.filter { $0.status == .inProgress }
            .map { StageGateOut(stageIndex: $0.index, status: GateOut(try store.stageGateStatus(stage: $0.index))) }
        let relearn = try stages.flatMap { try store.modules(stage: $0.index) }.filter(\.needsRelearn)
            .map { RelearnModuleOut(id: $0.id!, key: $0.key, title: $0.title, stageIndex: $0.stageIndex) }
        return try encode(ProgressOut(summary: store.progressSummary(), stageGates: gates, relearnModules: relearn))
    }

    /// 先校验全部题目都属于这次作答且已交卷，再逐题写入；raw 记录该题的原始评分对象。
    private func submitGrading(_ arguments: [String: JSONValue]) throws -> String {
        let args: GradingArgs = try decode(arguments)
        let detail = try store.attemptDetail(id: args.attemptId)
        guard detail.attempt.status != .inProgress else { throw StoreError.invalid("作答尚未提交，不能判卷") }
        guard !args.grades.isEmpty else { throw StoreError.invalid("grades 不能为空") }
        let ids = Set(detail.items.compactMap(\.problem.id))
        if let stray = args.grades.first(where: { !ids.contains($0.problemId) }) {
            throw StoreError.invalid("题目 \(stray.problemId) 不在这次作答中")
        }
        guard case .array(let rawGrades)? = arguments["grades"] else { throw StoreError.invalid("grades 必须是数组") }
        let grader = mcpName
        for (grade, raw) in zip(args.grades, rawGrades) {
            try store.recordGrade(attemptId: args.attemptId, problemId: grade.problemId, score: grade.score,
                                  feedback: grade.feedback, mistakes: grade.mistakes ?? [], grader: grader, raw: try encode(raw))
        }
        let updated = try store.attemptDetail(id: args.attemptId)
        return try encode(AttemptSummaryOut(attempt: updated.attempt, sections: updated.sections.map(SectionOut.init)))
    }

    // MARK: 编解码

    private func decode<T: Decodable>(_ arguments: [String: JSONValue]) throws -> T {
        let data = try JSONEncoder().encode(JSONValue.object(arguments))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context, _ key: CodingKey? = nil) -> String {
            let keys = context.codingPath + (key.map { [$0] } ?? [])
            let text = keys.map { $0.intValue.map { "[\($0)]" } ?? snakeCase($0.stringValue) }.joined(separator: ".")
            return text.isEmpty ? "参数" : text
        }
        switch error {
        case .keyNotFound(let key, let context): return "参数错误：缺少 \(path(context, key))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context): return "参数错误：\(path(context)) 类型不对"
        case .dataCorrupted(let context): return "参数错误：\(path(context)) 取值不合法"
        @unknown default: return "参数错误"
        }
    }

    private static func snakeCase(_ key: String) -> String {
        key.reduce(into: "") { result, ch in
            if ch.isUppercase { result += "_" + ch.lowercased() } else { result.append(ch) }
        }
    }
}

// MARK: 参数

private struct StageArgs: Decodable { var stageIndex: Int }
private struct OptionalStageArgs: Decodable { var stageIndex: Int? }
private struct CardsArgs: Decodable { var cards: [CardInput] }
private struct ProblemsArgs: Decodable { var problems: [ProblemInput] }
private struct AssignmentArgs: Decodable { var assignment: AssignmentInput }
private struct ExamArgs: Decodable { var exam: ExamInput }
private struct ExamIdArgs: Decodable { var examId: Int64 }
private struct AttemptsArgs: Decodable { var examId: Int64?; var status: AttemptStatus? }
private struct AttemptIdArgs: Decodable { var attemptId: Int64 }
private struct MistakesArgs: Decodable { var includeGraduated: Bool? }
private struct StageSettingsArgs: Decodable {
    var stageIndex: Int
    var passLine: Double?
    var cooldownDays: Int?
    var reward: String?
}
private struct GradingArgs: Decodable {
    struct Grade: Decodable {
        var problemId: Int64
        var score: Double
        var feedback: String
        var mistakes: [String]?
    }
    var attemptId: Int64
    var grades: [Grade]
}

// MARK: 输出

/// ProgressSummary 的字段平铺在顶层，再附加门槛与需重学模块。
private struct ProgressOut: Encodable {
    var summary: ProgressSummary
    var stageGates: [StageGateOut]
    var relearnModules: [RelearnModuleOut]

    private enum CodingKeys: String, CodingKey { case stageGates, relearnModules }

    func encode(to encoder: Encoder) throws {
        try summary.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stageGates, forKey: .stageGates)
        try container.encode(relearnModules, forKey: .relearnModules)
    }
}

private struct StageGateOut: Encodable {
    var stageIndex: Int
    var status: GateOut
}

private struct GateOut: Encodable {
    var kind: String
    var until: Day?
    var moduleId: Int64?
    init(_ status: StageGateStatus) {
        switch status {
        case .open: kind = "open"
        case .coolingDown(let day): kind = "coolingDown"; until = day
        case .needsRelearn(let id): kind = "needsRelearn"; moduleId = id
        case .locked: kind = "locked"
        case .alreadyPassed: kind = "alreadyPassed"
        }
    }
}

private struct RelearnModuleOut: Encodable {
    var id: Int64
    var key: String
    var title: String
    var stageIndex: Int
}

private struct StageOut: Encodable {
    var stage: Stage
    var modules: [Module]
}

private struct CreatedExamOut: Encodable {
    var examId: Int64
    var warnings: [String]
}

private struct SectionOut: Encodable {
    var title: String
    var earned: Double
    var max: Double
    var weight: Double
    var percent: Double
    init(_ s: SectionScore) { title = s.title; earned = s.earned; max = s.max; weight = s.weight; percent = s.percent }
}

private struct AttemptSummaryOut: Encodable {
    var attempt: Attempt
    var sections: [SectionOut]
}

private struct AttemptOut: Encodable {
    struct Item: Encodable {
        var problem: Problem
        var answer: String?
        var grades: [QuestionGrade]
    }
    var attempt: Attempt
    var sections: [SectionOut]
    var items: [Item]
    init(_ d: AttemptDetail) {
        attempt = d.attempt
        sections = d.sections.map(SectionOut.init)
        items = d.items.map { Item(problem: $0.problem, answer: $0.answer, grades: $0.grades) }
    }
}

private struct MistakeOut: Encodable {
    var mistake: Mistake
    var prompt: String
}

private struct TodayOut: Encodable {
    var dueCards: Int
    var deferredCards: Int
    var dueMistakes: Int
    var assignments: [Assignment]
    var readyExams: [Exam]
    var draftExams: Int
    var pendingGradingAttempts: Int
    var autoGen: String
    var autoGenErrors: [String]
    var noteWritten: Bool
    var progress: ProgressSummary
    init(_ t: TodaySummary) {
        dueCards = t.dueCards; deferredCards = t.deferredCards; dueMistakes = t.dueMistakes
        assignments = t.assignments; readyExams = t.readyExams; draftExams = t.draftExams; pendingGradingAttempts = t.pendingGradingAttempts
        noteWritten = t.noteWritten; progress = t.progress
        switch t.autoGen {
        case .disabled: autoGen = "disabled"; autoGenErrors = []
        case .notConfigured: autoGen = "notConfigured"; autoGenErrors = []
        case .running: autoGen = "running"; autoGenErrors = []
        case .done: autoGen = "done"; autoGenErrors = []
        case .failed(let errors): autoGen = "failed"; autoGenErrors = errors
        }
    }
}
