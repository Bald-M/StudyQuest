import Foundation
import GRDB

/// 按章节正文出闯关题与知识点卡片，并为一本教材的各节建议对应模块。生成成功后才写库。
public final class SectionChallengeService {
    static let source = "app_ai"
    static let problemCount = 5
    static let knowledgePointRange = 3...8

    private let store: StudyStore
    private let generation: GenerationService

    public init(store: StudyStore, model: @escaping () throws -> ChatModel) {
        self.store = store
        self.generation = GenerationService(store: store, model: model)
    }

    // MARK: 出题

    /// 没有需要重新生成的闯关时直接返回最新的，不调用 AI。
    public func prepareChallenge(sectionId: Int64) async throws -> (challengeId: Int64, truncated: Bool) {
        if try !store.challengeNeedsGeneration(sectionId: sectionId), let latest = try store.latestChallenge(sectionId: sectionId) {
            return (latest.id!, false)
        }
        let section = try store.section(id: sectionId)
        guard let book = try textbook(section.textbookId) else {
            throw StoreError.notFound("教材 \(section.textbookId)")
        }
        let module = try section.moduleId.map { try store.module(id: $0) }
        let needsCards = try !store.hasSectionCards(sectionId: sectionId)
        let stages = try store.stages()
        let modules = try stages.flatMap { try store.modules(stage: $0.index) }

        let truncated = section.text.count > SectionText.aiLimit
        let text = String(section.text.prefix(SectionText.aiLimit))
        var lines = [
            "请根据教材《\(book.title)》的「\(section.title)」一节出 \(Self.problemCount) 道题。",
            "只根据下面的正文出题，不要考正文没有讲到的内容。",
            "<正文>\n\(text)\n</正文>",
        ]
        if let module { lines.append(GenerationService.moduleContext(module)) }
        lines.append(GenerationService.difficultyGuidance(stage: book.stageIndex))
        lines.append("每道题的 stageIndex 必须是 \(book.stageIndex)，moduleKey 填 \(module.map { $0.key } ?? "null")。title 写本节闯关的标题。")
        if needsCards {
            lines.append("另外提炼 \(Self.knowledgePointRange.lowerBound)–\(Self.knowledgePointRange.upperBound) 个本节的知识点，"
                + "放在 knowledgePoints 里，每个包含 front（问题或术语）和 back（简明答案）。")
        }

        let output = try await generation.generate(
            Output.self, prompt: lines.joined(separator: "\n\n"), schema: Self.schema(needsCards: needsCards)
        ) { output in
            let problems = output.problems.map { problem -> ProblemInput in
                var problem = problem
                problem.stageIndex = book.stageIndex
                problem.moduleKey = module?.key
                return problem
            }
            let points = needsCards ? (output.knowledgePoints ?? []) : []
            let cards = points.map { CardInput(stageIndex: book.stageIndex, moduleKey: module?.key, front: $0.front, back: $0.back, tags: nil) }
            var errors: [String] = []
            if problems.count != Self.problemCount { errors.append("题目数量应为 \(Self.problemCount) 道，实际 \(problems.count) 道") }
            errors += problems.flatMap { ContentValidator.validate($0, stages: stages, modules: modules) }
            if needsCards {
                if !Self.knowledgePointRange.contains(cards.count) {
                    errors.append("知识点数量应为 \(Self.knowledgePointRange.lowerBound)–\(Self.knowledgePointRange.upperBound) 个，实际 \(cards.count) 个")
                }
                errors += cards.flatMap { ContentValidator.validate($0, stages: stages, modules: modules) }
            }
            return (errors, (problems, cards))
        }
        let (problems, cards) = output.checked
        let id = try store.createSectionChallenge(sectionId: sectionId, problems: problems, cards: cards, source: Self.source)
        return (id, truncated)
    }

    // MARK: 建议模块

    /// 只发送章节标题和该阶段的模块列表；不写库，由界面在用户确认后保存。
    public func suggestModules(textbookId: Int64) async throws -> [Int64: String?] {
        guard let book = try textbook(textbookId), book.deletedAt == nil else {
            throw StoreError.notFound("教材 \(textbookId)")
        }
        let sections = try store.sectionRows(textbookId: textbookId).map(\.section)
        guard !sections.isEmpty else { return [:] }
        let modules = try store.modules(stage: book.stageIndex)
        let prompt = """
            请为教材《\(book.title)》的每一节选出最相关的模块；没有合适的模块就填 null。
            各节（编号. 章 / 节）：
            \(sections.map { "\($0.id!). \($0.chapterTitle) / \($0.title)" }.joined(separator: "\n"))
            可选模块（key（名称））：
            \(modules.map { "\($0.key)（\($0.title)）" }.joined(separator: "\n"))
            mappings 里每节一项，sectionId 取自上面的编号，moduleKey 取自上面的模块 key 或 null。
            """
        let output = try await generation.generate(Mappings.self, prompt: prompt, schema: Self.mappingsSchema) { output in
            ([String](), output.mappings)
        }
        let validKeys = Set(modules.map(\.key))
        var chosen: [Int64: String] = [:]
        for item in output.checked {
            if let key = item.moduleKey, validKeys.contains(key) { chosen[item.sectionId] = key }
        }
        return Dictionary(uniqueKeysWithValues: sections.map { ($0.id!, chosen[$0.id!]) })
    }

    private func textbook(_ id: Int64) throws -> Textbook? {
        try store.pool.read { try Textbook.fetchOne($0, key: id) }
    }

    // MARK: 输出结构与 schema

    private struct Output: Decodable {
        struct Point: Decodable { var front: String; var back: String }
        var problems: [ProblemInput]
        var knowledgePoints: [Point]?
    }

    private struct Mappings: Decodable {
        struct Item: Decodable { var sectionId: Int64; var moduleKey: String? }
        var mappings: [Item]
    }

    private static func schema(needsCards: Bool) -> JSONValue {
        let string = GenerationService.string
        var properties: [String: JSONValue] = ["title": string, "problems": GenerationService.array(of: GenerationService.problemSchema)]
        var required = ["title", "problems"]
        if needsCards {
            properties["knowledgePoints"] = GenerationService.array(of: GenerationService.object(["front": string, "back": string], required: ["front", "back"]))
            required.append("knowledgePoints")
        }
        return GenerationService.object(properties, required: required)
    }

    private static let mappingsSchema = GenerationService.object([
        "mappings": GenerationService.array(of: GenerationService.object([
            "sectionId": GenerationService.integer,
            "moduleKey": .object(["type": .array([.string("string"), .string("null")])]),
        ], required: ["sectionId", "moduleKey"])),
    ], required: ["mappings"])
}
