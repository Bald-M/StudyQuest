import Foundation

/// AI 出题：作业、周测、阶段考试、卡片。输出先过 `ContentValidator`，有错让模型修正一次，仍有错抛 `StoreError.invalid`。
public final class GenerationService {
    static let source = "app_ai"

    private let store: StudyStore
    private let model: () throws -> ChatModel

    public init(store: StudyStore, model: @escaping () throws -> ChatModel) {
        self.store = store
        self.model = model
    }

    // MARK: 作业与卡片

    public func generateAssignment(moduleId: Int64, size: Int) async throws -> Int64 {
        let module = try store.module(id: moduleId)
        let stages = try store.stages()
        let modules = try allModules(stages)
        let prompt = """
            请为模块「\(module.title)」（key：\(module.key)，阶段 \(module.stageIndex)）出一份作业，共 \(size) 道题。
            \(Self.moduleContext(module))
            \(Self.difficultyGuidance(stage: module.stageIndex))
            每道题的 moduleKey 必须是 \(module.key)，stageIndex 必须是 \(module.stageIndex)。title 写作业标题。
            """
        let output = try await generate(ProblemsOutput.self, prompt: prompt, schema: Self.problemsSchema) { output in
            let problems = output.problems.map { Self.pin($0, to: module) }
            let errors = Self.titleErrors(output.title) + problems.flatMap { ContentValidator.validate($0, stages: stages, modules: modules) }
            return (errors, problems)
        }
        return try store.createAssignment(
            AssignmentInput(stageIndex: module.stageIndex, moduleKey: module.key, title: output.value.title, problemIds: nil,
                            problems: output.checked), source: Self.source)
    }

    public func generateCards(moduleId: Int64, count: Int) async throws -> [Int64] {
        let module = try store.module(id: moduleId)
        let stages = try store.stages()
        let modules = try allModules(stages)
        let prompt = """
            请为模块「\(module.title)」（key：\(module.key)，阶段 \(module.stageIndex)）制作 \(count) 张记忆卡片：正面是问题或术语，背面是简明答案。
            \(Self.moduleContext(module))
            每张卡片的 moduleKey 必须是 \(module.key)，stageIndex 必须是 \(module.stageIndex)。
            """
        let output = try await generate(CardsOutput.self, prompt: prompt, schema: Self.cardsSchema) { output in
            let cards = output.cards.map { card -> CardInput in
                var card = card
                card.moduleKey = module.key
                card.stageIndex = module.stageIndex
                return card
            }
            return (cards.flatMap { ContentValidator.validate($0, stages: stages, modules: modules) }, cards)
        }
        return try store.createCards(output.checked, source: Self.source)
    }

    // MARK: 试卷

    public func generateWeeklyQuiz() async throws -> Int64 {
        let stages = try store.stages()
        let modules = try allModules(stages)
        let thisWeek = try store.modulesStudiedThisWeek()
        let stageIndex: Int
        if let lowest = try store.learningModules().map(\.stageIndex).min() {
            stageIndex = lowest
        } else if let current = stages.first(where: { $0.status == .inProgress }) {
            stageIndex = current.index
        } else {
            throw StoreError.invalid("没有正在学习的模块或进行中的阶段，无法生成周测")
        }
        let thisWeekIds = Set(thisWeek.compactMap(\.id))
        let candidates = modules.filter { $0.stageIndex <= stageIndex && !thisWeekIds.contains($0.id!) }
        let studied = candidates.filter { $0.status != .notStarted }
        let earlier = Array((studied.isEmpty ? candidates : studied).suffix(6))
        let mistakes = try store.problems(ids: try store.dueMistakes().map(\.problemId)).prefix(10)

        var lines = ["请出一份周测，共 10 道题，覆盖已学内容。"]
        lines.append("本周学过的模块（约 80% 的题目来自这些模块）：\n" + Self.moduleList(thisWeek))
        lines.append("更早学过的模块（约 20% 的题目来自这些模块，用于巩固）：\n" + (earlier.isEmpty ? "（暂无）" : Self.moduleList(earlier)))
        if !mistakes.isEmpty {
            lines.append("以下是到期待复习的错题题干，可作为旧内容参考，出同类变式题，不要照抄：\n"
                + mistakes.map { "- " + String($0.prompt.prefix(80)) }.joined(separator: "\n"))
        }
        let contexts = (thisWeek + earlier).map(Self.moduleContext)
        lines.append("生活或游戏化素材：\n" + contexts.joined(separator: "\n"))
        lines.append(Self.difficultyGuidance(stage: stageIndex))
        lines.append("每道题的 moduleKey 必须取自上面的模块 key，stageIndex 必须等于该模块所属阶段。title 写周测标题。")

        let output = try await generate(ProblemsOutput.self, prompt: lines.joined(separator: "\n\n"), schema: Self.problemsSchema) { output in
            let problems = output.problems.map { Self.alignStage($0, modules: modules) }
            let exam = Self.weeklyExam(stage: stageIndex, title: output.title, problems: problems)
            return (Self.titleErrors(output.title) + ContentValidator.validate(exam, stages: stages, modules: modules), exam)
        }
        return try store.createExam(output.checked, source: Self.source).id
    }

    public func generateStageExam(stage: Int) async throws -> (id: Int64, warnings: [String]) {
        let info = try store.stage(stage)
        let stages = try store.stages()
        let modules = try allModules(stages)
        let percent = { (ratio: Double) in NumberText.whole(ratio * 100) }
        let moduleKeys = modules.filter { $0.stageIndex <= stage }.map { "\($0.key)（\($0.title)，阶段 \($0.stageIndex)）" }
        let prompt = """
            请为阶段 \(stage)「\(info.title)」出一份阶段考试。
            考试形式（附录 A）：\(info.summary)
            按这个形式设置分区（sections）与各分区权重（权重之和为 100）、timeLimitMinutes 与每个分区的题目；每个分区得分不低于 \(percent(info.minSectionRatio))% 才能过关，过关线 \(NumberText.whole(info.passLine))。
            累积题：全部题目中，来自更早阶段（stageIndex 小于 \(stage)）的题占 \(percent(info.cumulativeMin))%–\(percent(info.cumulativeMax))%。
            \(Self.difficultyGuidance(stage: stage))
            可用的模块 key：\n\(moduleKeys.joined(separator: "\n"))
            题目的 moduleKey 取自上面的模块，stageIndex 必须等于该模块所属阶段；不挂模块的题 moduleKey 填 null。
            """
        let output = try await generate(ExamOutput.self, prompt: prompt, schema: Self.examSchema) { output in
            let exam = ExamInput(
                stageIndex: stage, kind: .stageExam, title: output.title, timeLimitMinutes: output.timeLimitMinutes,
                sections: output.sections.map { section in
                    SectionInput(title: section.title, weight: section.weight, source: section.source, problemIds: nil,
                                 problems: section.problems?.map { Self.alignStage($0, modules: modules) })
                })
            return (Self.titleErrors(output.title) + ContentValidator.validate(exam, stages: stages, modules: modules), exam)
        }
        return try store.createExam(output.checked, source: Self.source)
    }

    // MARK: 生成与修正

    private struct Generated<Output, Checked> {
        var value: Output
        var checked: Checked
    }

    /// 解码并校验；有错把错误列表追加到对话里让模型修正一次，仍有错抛 `StoreError.invalid`。
    private func generate<Output: Decodable, Checked>(
        _ type: Output.Type, prompt: String, schema: JSONValue, check: (Output) -> (errors: [String], checked: Checked)
    ) async throws -> Generated<Output, Checked> {
        let chat = try model()
        var messages = [ChatMessage(role: "user", content: prompt)]
        func attempt() async throws -> (reply: String, result: Result<Generated<Output, Checked>, ErrorList>) {
            let reply = try await chat.complete(ChatRequest(system: Self.systemPrompt, messages: messages, jsonSchema: schema))
            let output: Output
            do { output = try JSONReply.decode(type, from: reply) } catch {
                return (reply, .failure(ErrorList(errors: ["输出不是符合要求的 JSON，无法解析"])))
            }
            let (errors, checked) = check(output)
            return (reply, errors.isEmpty ? .success(Generated(value: output, checked: checked)) : .failure(ErrorList(errors: errors)))
        }
        let first = try await attempt()
        guard case .failure(let problems) = first.result else { return try first.result.get() }
        messages.append(ChatMessage(role: "assistant", content: first.reply))
        messages.append(ChatMessage(role: "user", content: "上一次的输出有以下问题，请修正后重新输出完整 JSON：\n"
            + problems.errors.map { "- \($0)" }.joined(separator: "\n")))
        let second = try await attempt()
        switch second.result {
        case .success(let generated): return generated
        case .failure(let remaining): throw StoreError.invalid(remaining.errors.joined(separator: "；"))
        }
    }

    private struct ErrorList: Error { var errors: [String] }

    private func allModules(_ stages: [Stage]) throws -> [Module] {
        try stages.flatMap { try store.modules(stage: $0.index) }
    }

    // MARK: 输出结构

    private struct ProblemsOutput: Decodable {
        var title: String
        var problems: [ProblemInput]
    }

    private struct CardsOutput: Decodable {
        var cards: [CardInput]
    }

    private struct ExamOutput: Decodable {
        struct Section: Decodable {
            var title: String
            var weight: Double
            var source: SectionSource?
            var problems: [ProblemInput]?
        }
        var title: String
        var timeLimitMinutes: Int
        var sections: [Section]
    }

    private static func titleErrors(_ title: String) -> [String] {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ["标题不能为空"] : []
    }

    private static func pin(_ problem: ProblemInput, to module: Module) -> ProblemInput {
        var problem = problem
        problem.moduleKey = module.key
        problem.stageIndex = module.stageIndex
        return problem
    }

    /// 题目挂了模块时，阶段以模块所属阶段为准。
    private static func alignStage(_ problem: ProblemInput, modules: [Module]) -> ProblemInput {
        guard let key = problem.moduleKey, let module = modules.first(where: { $0.key == key }) else { return problem }
        var problem = problem
        problem.stageIndex = module.stageIndex
        return problem
    }

    private static func weeklyExam(stage: Int, title: String, problems: [ProblemInput]) -> ExamInput {
        ExamInput(stageIndex: stage, kind: .weeklyQuiz, title: title, timeLimitMinutes: 30,
                  sections: [SectionInput(title: "周测", weight: 100, source: .problems, problemIds: nil, problems: problems)])
    }

    // MARK: 提示文本

    private static let systemPrompt = """
        你是编程自学路线里的出题老师。严格按照用户给出的要求出题，题目、参考答案与评分标准（rubric）都用中文，\
        参考答案要完整正确，rubric 写清各得分点。只输出符合 schema 的 JSON，不要任何其他文字。
        """

    private static func difficultyGuidance(stage: Int) -> String {
        stage <= 1
            ? "难度：阶段 \(stage) 以简单题为主（difficulty 多数为 easy，少量 medium）。"
            : "难度：阶段 \(stage) 简单与中等各占一半（easy 与 medium 各约 50%）。"
    }

    private static func moduleContext(_ module: Module) -> String {
        var parts = ["模块「\(module.title)」要点：\(module.points)"]
        if !module.lifeProblems.isEmpty { parts.append("贴近生活的题材：" + module.lifeProblems.joined(separator: "、")) }
        if !module.gameTasks.isEmpty { parts.append("游戏化素材：" + module.gameTasks.joined(separator: "、")) }
        return parts.joined(separator: "；") + "。题目要贴近生活或游戏化。"
    }

    private static func moduleList(_ modules: [Module]) -> String {
        modules.map { "- \($0.title)（key：\($0.key)，阶段 \($0.stageIndex)）" }.joined(separator: "\n")
    }

    // MARK: Schema

    private static func object(_ properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map { .string($0) }),
                 "additionalProperties": .bool(false)])
    }

    private static func array(of items: JSONValue) -> JSONValue { .object(["type": .string("array"), "items": items]) }
    private static let string: JSONValue = .object(["type": .string("string")])
    private static let number: JSONValue = .object(["type": .string("number")])
    private static let integer: JSONValue = .object(["type": .string("integer")])
    private static func stringEnum(_ values: [String]) -> JSONValue {
        .object(["type": .string("string"), "enum": .array(values.map { .string($0) })])
    }

    private static let problemSchema = object([
        "stageIndex": integer,
        "moduleKey": .object(["type": .array([.string("string"), .string("null")])]),
        "kind": stringEnum(["singleChoice", "multipleChoice", "shortAnswer", "coding", "project"]),
        "prompt": string,
        "options": array(of: string),
        "referenceAnswer": string,
        "rubric": string,
        "maxScore": number,
        "difficulty": stringEnum(["easy", "medium", "hard"]),
        "tags": array(of: string),
    ], required: ["stageIndex", "kind", "prompt", "referenceAnswer", "rubric", "maxScore", "difficulty"])

    static let problemsSchema = object(["title": string, "problems": array(of: problemSchema)], required: ["title", "problems"])

    static let cardsSchema = object([
        "cards": array(of: object([
            "stageIndex": integer,
            "moduleKey": .object(["type": .array([.string("string"), .string("null")])]),
            "front": string,
            "back": string,
            "tags": array(of: string),
        ], required: ["stageIndex", "front", "back"])),
    ], required: ["cards"])

    static let examSchema = object([
        "title": string,
        "timeLimitMinutes": integer,
        "sections": array(of: object([
            "title": string,
            "weight": number,
            "source": stringEnum(["problems", "mockInterviewAverage"]),
            "problems": array(of: problemSchema),
        ], required: ["title", "weight"])),
    ], required: ["title", "timeLimitMinutes", "sections"])
}
