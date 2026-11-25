import Foundation
import StudyCore

/// 一个 MCP 提示模板的名字、说明与参数（与 SDK 无关，MCPServer 负责转换）。
public struct PromptSpec: Sendable {
    public struct Argument: Sendable {
        public var name: String
        public var description: String
        public var required: Bool
    }
    public var name: String
    public var description: String
    public var arguments: [Argument]
}

/// 设计文档 §10.2 的 3 个提示模板：把库里的相关数据拼进提示，并说明应调用哪些工具。
public enum PromptCatalog {
    public static let prompts: [PromptSpec] = [
        PromptSpec(name: "generate_stage_exam", description: "按阶段大纲与过关规则生成阶段考试，并调用 create_exam 写入。",
                   arguments: [.init(name: "stage_index", description: "阶段序号 0–9", required: true)]),
        PromptSpec(name: "generate_weekly_quiz", description: "按本周学过的模块和到期错题生成周测（80% 本周 + 20% 旧内容）。", arguments: []),
        PromptSpec(name: "analyze_weakness", description: "根据最近的作答记录分析薄弱点并建议作业。", arguments: []),
    ]

    /// 参数值可以是数字或字符串（MCP 客户端通常以字符串传递提示参数）。
    public static func render(name: String, arguments: [String: JSONValue], store: StudyStore) throws -> String {
        switch name {
        case "generate_stage_exam": return try stageExam(stageIndex: stageIndex(arguments), store: store)
        case "generate_weekly_quiz": return try weeklyQuiz(store: store)
        case "analyze_weakness": return try weakness(store: store)
        default: throw StoreError.invalid("未知提示模板：\(name)")
        }
    }

    private static func stageIndex(_ arguments: [String: JSONValue]) throws -> Int {
        switch arguments["stage_index"] {
        case .number(let n)?: return Int(n)
        case .string(let s)?: if let n = Int(s.trimmingCharacters(in: .whitespaces)) { return n }
        default: break
        }
        throw StoreError.invalid("参数错误：stage_index 必须是 0–9 的整数")
    }

    private static func percent(_ ratio: Double) -> String { "\(Int((ratio * 100).rounded()))%" }

    private static func stageExam(stageIndex: Int, store: StudyStore) throws -> String {
        let stage = try store.stage(stageIndex)
        let modules = try store.modules(stage: stageIndex)
        let outline = modules.map { "- \($0.title)（key: \($0.key)）：\($0.points)" }.joined(separator: "\n")
        let cumulative = stageIndex == 0
            ? "阶段 0 没有更早的阶段，不需要累积题。"
            : "累积题（来自阶段 0–\(stageIndex - 1) 的题目）占全部题目的 \(percent(stage.cumulativeMin))–\(percent(stage.cumulativeMax))。"
        return """
            请为 StudyQuest 的阶段 \(stage.index)「\(stage.title)」出一份阶段考试。

            ## 阶段大纲
            \(stage.summary)
            预计用时：\(stage.estimatedWeeks)
            模块：
            \(outline)

            ## 过关规则
            - 总分达到 \(Int(stage.passLine)) 分（百分制）才算通过。
            - 每个分区得分不得低于该分区满分的 \(percent(stage.minSectionRatio))。
            - 未通过后冷却 \(stage.cooldownDays) 天才能重考，重考需要一张新卷，不要与旧卷重复。

            ## 题型配比与累积要求
            - 题型与分区按上面大纲中"考试"的形式安排（理论/上机等分区及其权重），各分区权重之和必须为 100。
            - \(cumulative)
            - 每道题写清参考答案（reference_answer）和评分标准（rubric），满分为正数；选择题必须给出选项。

            ## 操作步骤
            1. 需要更多细节时调用 get_stage（stage_index: \(stage.index)）。
            2. 调用 create_exam，kind 设为 "stageExam"，stage_index 设为 \(stage.index)，题目可内联在各分区的 problems 中。
            3. 检查返回的 warnings（累积题占比、重复题），必要时调整后重新创建。
            """
    }

    private static func weeklyQuiz(store: StudyStore) throws -> String {
        let modules = try store.modulesStudiedThisWeek()
        let mistakes = try store.dueMistakes()
        let prompts = try store.problems(ids: mistakes.map(\.problemId))
        let stage = try store.progressSummary().currentStage
        let moduleList = modules.isEmpty ? "（本周没有学习记录，按当前阶段的模块出题）"
            : modules.map { "- 阶段 \($0.stageIndex)「\($0.title)」（key: \($0.key)）：\($0.points)" }.joined(separator: "\n")
        let mistakeList = prompts.isEmpty ? "（没有到期错题）"
            : prompts.map { "- 题目 \($0.id!)：\($0.prompt)" }.joined(separator: "\n")
        return """
            请为 StudyQuest 出一份本周周测，当前阶段为 \(stage)。

            ## 本周学过的模块
            \(moduleList)

            ## 到期错题
            \(mistakeList)

            ## 要求
            - 约 80% 的题目考本周学过的模块，约 20% 考更早学过的旧内容（可参考到期错题，换一种问法）。
            - 每道题写清参考答案（reference_answer）和评分标准（rubric），满分为正数；选择题必须给出选项。
            - 周测过关线为 75%。

            ## 操作步骤
            1. 需要模块细节时调用 get_stage。
            2. 调用 create_exam，kind 设为 "weeklyQuiz"，stage_index 设为 \(stage)，分区权重之和为 100。
            """
    }

    private static func weakness(store: StudyStore) throws -> String {
        let attempts = Array(try store.attempts(examId: nil, status: .graded).prefix(10))
        let attemptList = attempts.isEmpty ? "（还没有已判卷的作答）" : attempts.map { a in
            let score = a.totalPercent.map { "\(Int($0.rounded()))%" } ?? "无总分"
            let passed = a.passed.map { $0 ? "通过" : "未通过" } ?? ""
            return "- 作答 \(a.id!)（\(a.kind.rawValue)）：\(score) \(passed)"
        }.joined(separator: "\n")
        let mistakes = try store.mistakes(includeGraduated: false)
        let prompts = try store.problems(ids: mistakes.map(\.problemId))
        let mistakeList = prompts.isEmpty ? "（没有未毕业的错题）"
            : prompts.map { "- 题目 \($0.id!)（阶段 \($0.stageIndex)）：\($0.prompt)" }.joined(separator: "\n")
        return """
            请分析 StudyQuest 学习者最近的薄弱点，并建议针对性作业。

            ## 最近已判卷的作答（最多 10 次）
            \(attemptList)

            ## 未毕业的错题
            \(mistakeList)

            ## 操作步骤
            1. 用 get_attempt 查看上面作答的每题得分、反馈和错误点；需要时用 list_attempts、list_mistakes 补充。
            2. 总结 2–4 个薄弱知识点，说明依据（哪些题、错在哪里）。
            3. 为每个薄弱点建议一份作业；学习者同意后调用 create_assignment 创建。
            """
    }
}
