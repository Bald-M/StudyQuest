import Foundation
import GRDB

public enum SettingKey: String, Sendable, CaseIterable {
    case dailyNewCardLimit, reviewDisplayCap, autoGenEnabled, autoGenDailyMax, assignmentSize
    case gradingProviderId, generationProviderId

    public var defaultValue: String {
        switch self {
        case .dailyNewCardLimit: "20"
        case .reviewDisplayCap: "100"
        case .autoGenEnabled: "true"
        case .autoGenDailyMax: "3"
        case .assignmentSize: "5"
        case .gradingProviderId, .generationProviderId: ""
        }
    }
}

public struct ExamDetail: Codable, Sendable {
    public struct Section: Codable, Sendable {
        public var section: ExamSection
        public var problems: [Problem]
    }
    public var exam: Exam
    public var sections: [Section]
}

extension StudyStore {
    // MARK: 设置

    public func setting(_ key: SettingKey) throws -> String {
        try pool.read { try AppSetting.fetchOne($0, key: key.rawValue)?.value } ?? key.defaultValue
    }

    public func setSetting(_ key: SettingKey, _ value: String) throws {
        try pool.write { try AppSetting(key: key.rawValue, value: value).save($0) }
        notifier.post()
    }

    // MARK: 卡片

    public func createCards(_ inputs: [CardInput], source: String) throws -> [Int64] {
        let (stages, modules) = try catalog()
        try Self.require(inputs.flatMap { ContentValidator.validate($0, stages: stages, modules: modules) })
        let now = clock.now()
        let today = clock.today()
        let ids = try pool.write { db in
            try inputs.map { input -> Int64 in
                var card = Card(
                    stageIndex: input.stageIndex, moduleId: Self.moduleId(input.moduleKey, in: modules),
                    front: input.front, back: input.back, tags: input.tags ?? [], step: nil, dueDay: today, createdAt: now)
                try card.insert(db)
                return card.id!
            }
        }
        notifier.post()
        return ids
    }

    public func reviewQueue() throws -> (cards: [Card], deferred: Int) {
        let today = clock.today()
        let newLimit = Int(try setting(.dailyNewCardLimit)) ?? 20
        let cap = Int(try setting(.reviewDisplayCap)) ?? 100
        let (due, new, introducedToday) = try pool.read { db in
            (try Card.filter(Column("step") != nil && Column("dueDay") <= today.rawValue).fetchAll(db),
             try Card.filter(Column("step") == nil).order(Column("id")).fetchAll(db),
             // 今天第一次被复习的卡数：每日新卡上限按天累计
             try Int.fetchOne(db, sql: """
                 SELECT COUNT(*) FROM (SELECT cardId FROM cardReview GROUP BY cardId HAVING MIN(day) = ?)
                 """, arguments: [today.rawValue]) ?? 0)
        }
        return ReviewScheduler.queue(due: due, new: new, newLimit: max(0, newLimit - introducedToday), displayCap: cap, today: today)
    }

    public func recordReview(cardId: Int64, remembered: Bool) throws {
        let today = clock.today()
        try pool.write { db in
            guard var card = try Card.fetchOne(db, key: cardId) else { throw StoreError.notFound("卡片 \(cardId)") }
            let next = ReviewScheduler.nextCard(step: card.step, remembered: remembered, today: today, calendar: clock.calendar)
            card.step = next.step
            card.dueDay = next.due
            try card.update(db)
            var review = CardReview(cardId: cardId, day: today, remembered: remembered)
            try review.insert(db)
        }
        defer { notifier.post() }
        if try reviewQueue().cards.isEmpty {
            try awardXP(dedupKey: "review:\(today.rawValue)", amount: XPRules.reviewCleared, reason: .reviewCleared, day: today)
        }
    }

    // MARK: 题目与作业

    public func createProblems(_ inputs: [ProblemInput], source: String) throws -> [Int64] {
        let (stages, modules) = try catalog()
        try Self.require(inputs.flatMap { ContentValidator.validate($0, stages: stages, modules: modules) })
        let now = clock.now()
        let ids = try pool.write { try Self.insertProblems(inputs, source: source, modules: modules, now: now, db: $0) }
        notifier.post()
        return ids
    }

    public func problems(ids: [Int64]) throws -> [Problem] {
        let found = try pool.read { try Problem.fetchAll($0, keys: ids) }
        let byId = Dictionary(uniqueKeysWithValues: found.compactMap { p in p.id.map { ($0, p) } })
        return ids.compactMap { byId[$0] }
    }

    public func createAssignment(_ input: AssignmentInput, source: String) throws -> Int64 {
        let (stages, modules) = try catalog()
        var errors = ContentValidator.validate(
            ProblemInput(stageIndex: input.stageIndex, moduleKey: input.moduleKey, kind: .shortAnswer, prompt: "-", options: nil,
                         referenceAnswer: "-", rubric: "", maxScore: 1, difficulty: .easy, tags: nil),
            stages: stages, modules: modules)
        if input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("作业标题不能为空") }
        if (input.problemIds?.count ?? 0) + (input.problems?.count ?? 0) == 0 { errors.append("作业至少需要 1 道题") }
        errors += (input.problems ?? []).flatMap { ContentValidator.validate($0, stages: stages, modules: modules) }
        try Self.require(errors)
        let now = clock.now()
        let today = clock.today()
        let id = try pool.write { db -> Int64 in
            let existing = input.problemIds ?? []
            guard try Problem.filter(keys: existing).fetchCount(db) == Set(existing).count else {
                throw StoreError.invalid("problemIds 中有题目不存在")
            }
            let created = try Self.insertProblems(input.problems ?? [], source: source, modules: modules, now: now, db: db)
            var assignment = Assignment(
                stageIndex: input.stageIndex, moduleId: Self.moduleId(input.moduleKey, in: modules), day: today,
                title: input.title, problemIds: existing + created, status: .open, source: source, createdAt: now)
            try assignment.insert(db)
            return assignment.id!
        }
        notifier.post()
        return id
    }

    public func assignments(day: Day) throws -> [Assignment] {
        try pool.read { try Assignment.filter(Column("day") == day.rawValue).order(Column("id")).fetchAll($0) }
    }

    public func openAssignments() throws -> [Assignment] {
        try pool.read {
            try Assignment.filter(Column("status") == AssignmentStatus.open.rawValue).order(Column("day"), Column("id")).fetchAll($0)
        }
    }

    public func completedAssignments() throws -> [Assignment] {
        try pool.read {
            try Assignment.filter(Column("status") == AssignmentStatus.completed.rawValue).order(Column("day").desc, Column("id").desc).fetchAll($0)
        }
    }

    // MARK: 试卷

    public func createExam(_ input: ExamInput, source: String) throws -> (id: Int64, warnings: [String]) {
        let (stages, modules) = try catalog()
        try Self.require(ContentValidator.validate(input, stages: stages, modules: modules))
        guard let stage = stages.first(where: { $0.index == input.stageIndex }) else { throw StoreError.notFound("阶段 \(input.stageIndex)") }
        let now = clock.now()
        let result = try pool.write { db -> (Int64, [String]) in
            var sectionProblemIds: [[Int64]] = []
            for section in input.sections {
                let existing = section.problemIds ?? []
                guard try Problem.filter(keys: existing).fetchCount(db) == Set(existing).count else {
                    throw StoreError.invalid("problemIds 中有题目不存在")
                }
                let created = try Self.insertProblems(section.problems ?? [], source: source, modules: modules, now: now, db: db)
                sectionProblemIds.append(existing + created)
            }
            let all = try Problem.fetchAll(db, keys: sectionProblemIds.flatMap { $0 })

            var warnings: [String] = []
            if input.kind == .stageExam {
                if let w = ExamChecks.cumulativeWarning(
                    stageIndex: input.stageIndex, problemStageIndices: all.map(\.stageIndex),
                    min: stage.cumulativeMin, max: stage.cumulativeMax) { warnings.append(w) }
                let previous = try Exam.filter(Column("stageIndex") == input.stageIndex && Column("kind") == ExamKind.stageExam.rawValue).fetchAll(db)
                let previousProblemIds = try previous.flatMap { exam in
                    try ExamSection.filter(Column("examId") == exam.id!).fetchAll(db).flatMap(\.problemIds)
                }
                let previousPrompts = try Problem.fetchAll(db, keys: previousProblemIds).map(\.prompt)
                if let w = ExamChecks.overlapWarning(newPrompts: all.map(\.prompt), previousPrompts: previousPrompts) { warnings.append(w) }
            }

            var exam = Exam(
                stageIndex: input.stageIndex, kind: input.kind, title: input.title, timeLimitMinutes: input.timeLimitMinutes,
                status: .ready, warnings: warnings, source: source, createdAt: now)
            try exam.insert(db)
            for (i, section) in input.sections.enumerated() {
                var row = ExamSection(
                    examId: exam.id!, order: i, title: section.title, weight: section.weight,
                    sourceKind: section.source ?? .problems, problemIds: sectionProblemIds[i])
                try row.insert(db)
            }
            return (exam.id!, warnings)
        }
        notifier.post()
        return (id: result.0, warnings: result.1)
    }

    public func exams(stage: Int?) throws -> [Exam] {
        try pool.read { db in
            var request = Exam.order(Column("id"))
            if let stage { request = request.filter(Column("stageIndex") == stage) }
            return try request.fetchAll(db)
        }
    }

    public func examDetail(id: Int64, revealAnswers: Bool) throws -> ExamDetail {
        try pool.read { db in
            guard let exam = try Exam.fetchOne(db, key: id) else { throw StoreError.notFound("试卷 \(id)") }
            let sections = try ExamSection.filter(Column("examId") == id).order(Column("order")).fetchAll(db)
            let details = try sections.map { section -> ExamDetail.Section in
                let found = try Problem.fetchAll(db, keys: section.problemIds)
                let byId = Dictionary(uniqueKeysWithValues: found.compactMap { p in p.id.map { ($0, p) } })
                var problems = section.problemIds.compactMap { byId[$0] }
                if !revealAnswers {
                    for i in problems.indices { problems[i].referenceAnswer = ""; problems[i].rubric = "" }
                }
                return ExamDetail.Section(section: section, problems: problems)
            }
            return ExamDetail(exam: exam, sections: details)
        }
    }

    // MARK: 内部

    private func catalog() throws -> ([Stage], [Module]) {
        let stages = try self.stages()
        return (stages, try stages.flatMap { try modules(stage: $0.index) })
    }

    private static func require(_ errors: [String]) throws {
        if !errors.isEmpty { throw StoreError.invalid(errors.joined(separator: "；")) }
    }

    private static func moduleId(_ key: String?, in modules: [Module]) -> Int64? {
        key.flatMap { key in modules.first { $0.key == key }?.id }
    }

    private static func insertProblems(_ inputs: [ProblemInput], source: String, modules: [Module], now: Date, db: Database) throws -> [Int64] {
        try inputs.map { input in
            var problem = Problem(
                stageIndex: input.stageIndex, moduleId: moduleId(input.moduleKey, in: modules), kind: input.kind,
                prompt: input.prompt, options: input.options ?? [], referenceAnswer: input.referenceAnswer, rubric: input.rubric,
                maxScore: input.maxScore, difficulty: input.difficulty, tags: input.tags ?? [], source: source, createdAt: now)
            try problem.insert(db)
            return problem.id!
        }
    }
}
