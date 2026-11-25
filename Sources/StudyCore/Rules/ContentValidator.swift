import Foundation

public struct CardInput: Codable, Sendable {
    public var stageIndex: Int
    public var moduleKey: String?
    public var front: String
    public var back: String
    public var tags: [String]?
    public init(stageIndex: Int, moduleKey: String?, front: String, back: String, tags: [String]?) {
        self.stageIndex = stageIndex; self.moduleKey = moduleKey; self.front = front; self.back = back; self.tags = tags
    }
}

public struct ProblemInput: Codable, Sendable {
    public var stageIndex: Int
    public var moduleKey: String?
    public var kind: ProblemKind
    public var prompt: String
    public var options: [String]?
    public var referenceAnswer: String
    public var rubric: String
    public var maxScore: Double
    public var difficulty: Difficulty
    public var tags: [String]?
    public init(stageIndex: Int, moduleKey: String?, kind: ProblemKind, prompt: String, options: [String]?, referenceAnswer: String, rubric: String, maxScore: Double, difficulty: Difficulty, tags: [String]?) {
        self.stageIndex = stageIndex; self.moduleKey = moduleKey; self.kind = kind; self.prompt = prompt; self.options = options
        self.referenceAnswer = referenceAnswer; self.rubric = rubric; self.maxScore = maxScore; self.difficulty = difficulty; self.tags = tags
    }
}

public struct SectionInput: Codable, Sendable {
    public var title: String
    public var weight: Double
    public var source: SectionSource?
    public var problemIds: [Int64]?
    public var problems: [ProblemInput]?
    public init(title: String, weight: Double, source: SectionSource?, problemIds: [Int64]?, problems: [ProblemInput]?) {
        self.title = title; self.weight = weight; self.source = source; self.problemIds = problemIds; self.problems = problems
    }
}

public struct ExamInput: Codable, Sendable {
    public var stageIndex: Int
    public var kind: ExamKind
    public var title: String
    public var timeLimitMinutes: Int
    public var sections: [SectionInput]
    public init(stageIndex: Int, kind: ExamKind, title: String, timeLimitMinutes: Int, sections: [SectionInput]) {
        self.stageIndex = stageIndex; self.kind = kind; self.title = title; self.timeLimitMinutes = timeLimitMinutes; self.sections = sections
    }
}

public struct AssignmentInput: Codable, Sendable {
    public var stageIndex: Int
    public var moduleKey: String?
    public var title: String
    public var problemIds: [Int64]?
    public var problems: [ProblemInput]?
    public init(stageIndex: Int, moduleKey: String?, title: String, problemIds: [Int64]?, problems: [ProblemInput]?) {
        self.stageIndex = stageIndex; self.moduleKey = moduleKey; self.title = title; self.problemIds = problemIds; self.problems = problems
    }
}

/// 校验 MCP 与 AI 生成共用的输入；返回中文错误列表，空表示合法。
public enum ContentValidator {
    public static func validate(_ p: ProblemInput, stages: [Stage], modules: [Module]) -> [String] {
        var errors = location(stage: p.stageIndex, moduleKey: p.moduleKey, stages: stages, modules: modules)
        if p.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("题干不能为空") }
        if p.referenceAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("参考答案不能为空") }
        if !(p.maxScore > 0) { errors.append("满分必须大于 0") }
        if p.kind == .singleChoice || p.kind == .multipleChoice, (p.options?.count ?? 0) < 2 {
            errors.append("选择题至少需要 2 个选项")
        }
        return errors
    }

    public static func validate(_ c: CardInput, stages: [Stage], modules: [Module]) -> [String] {
        var errors = location(stage: c.stageIndex, moduleKey: c.moduleKey, stages: stages, modules: modules)
        if c.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("卡片正面不能为空") }
        if c.back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("卡片背面不能为空") }
        return errors
    }

    public static func validate(_ e: ExamInput, stages: [Stage], modules: [Module]) -> [String] {
        var errors: [String] = []
        if !stages.contains(where: { $0.index == e.stageIndex }) { errors.append("阶段 \(e.stageIndex) 不存在") }
        if e.timeLimitMinutes <= 0 { errors.append("限时必须大于 0 分钟") }
        if e.sections.isEmpty { errors.append("试卷至少需要 1 个分区") }
        if abs(e.sections.map(\.weight).reduce(0, +) - 100) > 0.01 { errors.append("各分区权重之和必须为 100") }
        for (i, s) in e.sections.enumerated() {
            let name = "分区 \(i + 1)"
            switch s.source ?? .problems {
            case .problems:
                if (s.problemIds?.count ?? 0) + (s.problems?.count ?? 0) == 0 { errors.append("\(name)至少需要 1 道题") }
            case .mockInterviewAverage:
                if e.stageIndex != 9 { errors.append("\(name)：模拟面试均分分区只允许出现在阶段 9") }
            }
            for p in s.problems ?? [] {
                errors += validate(p, stages: stages, modules: modules).map { "\(name)：\($0)" }
            }
        }
        return errors
    }

    private static func location(stage: Int, moduleKey: String?, stages: [Stage], modules: [Module]) -> [String] {
        guard stages.contains(where: { $0.index == stage }) else { return ["阶段 \(stage) 不存在"] }
        guard let moduleKey else { return [] }
        guard let module = modules.first(where: { $0.key == moduleKey }) else { return ["模块 \(moduleKey) 不存在"] }
        return module.stageIndex == stage ? [] : ["模块 \(moduleKey) 不属于阶段 \(stage)"]
    }
}
