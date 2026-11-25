import Foundation
import GRDB

/// 首次打开空库时写入内置路线。必须在一个写事务内调用。
enum Seeder {
    private struct Payload: Decodable {
        struct StageEntry: Decodable {
            var index: Int
            var title: String
            var estimatedWeeks: String
            var passLine: Double
            var summary: String
            var resources: [String]
            var gameTasks: [String]
            var lifeProblems: [String]
            var modules: [[String]]
        }
        struct CardEntry: Decodable { var module: String; var front: String; var back: String; var tags: [String] }
        struct ProblemEntry: Decodable {
            var module: String
            var kind: ProblemKind
            var difficulty: Difficulty
            var prompt: String
            var options: [String]
            var referenceAnswer: String
            var rubric: String
            var maxScore: Double
            var tags: [String]
        }
        var stages: [StageEntry]
        var stageZeroCards: [CardEntry]
        var stageZeroProblems: [ProblemEntry]
    }

    static func seedIfEmpty(_ db: Database, now: Date, today: Day) throws {
        guard try Stage.fetchCount(db) == 0 else { return }
        let payload = try JSONDecoder().decode(Payload.self, from: Data(CurriculumData.json.utf8))

        var moduleIds: [String: Int64] = [:]
        for entry in payload.stages {
            var stage = Stage(
                index: entry.index, title: entry.title, summary: entry.summary,
                estimatedWeeks: entry.estimatedWeeks, passLine: entry.passLine,
                minSectionRatio: 0.6, cumulativeMin: 0.2, cumulativeMax: 0.3, cooldownDays: 3,
                status: entry.index == 0 ? .inProgress : .locked
            )
            try stage.insert(db)
            for (order, parts) in entry.modules.enumerated() {
                var module = Module(
                    stageIndex: entry.index, key: parts[0], title: parts[1], points: parts[2],
                    resources: entry.resources, gameTasks: entry.gameTasks, lifeProblems: entry.lifeProblems,
                    order: order, status: .notStarted, needsRelearn: false)
                try module.insert(db)
                moduleIds[module.key] = module.id
            }
        }
        for c in payload.stageZeroCards {
            var card = Card(stageIndex: 0, moduleId: moduleIds[c.module], front: c.front, back: c.back,
                            tags: c.tags, step: nil, dueDay: today, createdAt: now)
            try card.insert(db)
        }
        for p in payload.stageZeroProblems {
            var problem = Problem(
                stageIndex: 0, moduleId: moduleIds[p.module], kind: p.kind, prompt: p.prompt, options: p.options,
                referenceAnswer: p.referenceAnswer, rubric: p.rubric, maxScore: p.maxScore,
                difficulty: p.difficulty, tags: p.tags, source: "seed", createdAt: now)
            try problem.insert(db)
        }
    }
}
