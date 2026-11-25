import Foundation
import GRDB
import Testing
@testable import StudyCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func makeStore(clock: FixedClock = FixedClock(t0)) throws -> StudyStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
    return try StudyStore(database: AppDatabase(url: dir.appendingPathComponent("test.sqlite")), clock: clock, notifier: NoopChangeNotifier())
}

private func problem(stage: Int = 0, prompt: String = "题干", kind: ProblemKind = .shortAnswer, options: [String]? = nil,
                     max: Double = 10, moduleKey: String? = nil) -> ProblemInput {
    ProblemInput(stageIndex: stage, moduleKey: moduleKey, kind: kind, prompt: prompt, options: options,
                 referenceAnswer: "答案", rubric: "评分标准", maxScore: max, difficulty: .medium, tags: nil)
}

@Suite struct ContentTests {
    @Test func validatorCatchesBadInput() throws {
        let store = try makeStore()
        let stages = try store.stages()
        let modules = try stages.flatMap { try store.modules(stage: $0.index) }
        let otherStageKey = try #require(modules.first { $0.stageIndex == 1 }).key

        let bad = problem(kind: .singleChoice, options: ["A"], max: 0, moduleKey: otherStageKey)
        #expect(ContentValidator.validate(bad, stages: stages, modules: modules).count == 3)
        #expect(ContentValidator.validate(problem(), stages: stages, modules: modules).isEmpty)

        let section = SectionInput(title: "A", weight: 90, source: nil, problemIds: nil, problems: [problem()])
        let exam = ExamInput(stageIndex: 0, kind: .weeklyQuiz, title: "T", timeLimitMinutes: 30, sections: [section])
        #expect(ContentValidator.validate(exam, stages: stages, modules: modules).contains { $0.contains("权重") })

        let mock = SectionInput(title: "面试", weight: 100, source: .mockInterviewAverage, problemIds: nil, problems: nil)
        let exam3 = ExamInput(stageIndex: 3, kind: .stageExam, title: "T", timeLimitMinutes: 30, sections: [mock])
        #expect(!ContentValidator.validate(exam3, stages: stages, modules: modules).isEmpty)
    }

    @Test func createExamWritesWarnings() throws {
        let store = try makeStore()
        let probs = (0..<10).map { problem(stage: 3, prompt: "题 \($0)") }
        let section = SectionInput(title: "A", weight: 100, source: .problems, problemIds: nil, problems: probs)
        let exam = ExamInput(stageIndex: 3, kind: .stageExam, title: "阶段 3", timeLimitMinutes: 60, sections: [section])
        let result = try store.createExam(exam, source: "test")
        #expect(result.warnings.contains { $0.contains("累积题占比") })
        let stored = try #require(try store.exams(stage: 3).first)
        #expect(stored.status == .ready)
        #expect(stored.warnings == result.warnings)

        let second = try store.createExam(exam, source: "test")
        #expect(second.warnings.contains { $0.contains("重复") })
    }

    @Test func draftCannotBeStarted() throws {
        let store = try makeStore()
        let section = SectionInput(title: "A", weight: 100, source: .problems, problemIds: nil, problems: [problem()])
        let id = try store.createExam(ExamInput(stageIndex: 0, kind: .weeklyQuiz, title: "草稿周测", timeLimitMinutes: 20, sections: [section]),
                                      source: "test", status: .draft).id
        #expect(try store.examDetail(id: id, revealAnswers: false).exam.status == .draft)
        #expect(throws: StoreError.invalid("试卷还是草稿，请先确认")) { try store.startExam(id: id) }
        #expect(try store.attempts(examId: id, status: nil).isEmpty)
    }

    @Test func confirmAndDiscardDraft() throws {
        let store = try makeStore()
        let section = SectionInput(title: "A", weight: 100, source: .problems, problemIds: nil, problems: [problem()])
        let input = ExamInput(stageIndex: 0, kind: .weeklyQuiz, title: "草稿周测", timeLimitMinutes: 20, sections: [section])

        let kept = try store.createExam(input, source: "test", status: .draft).id
        try store.confirmExam(id: kept)
        #expect(try store.examDetail(id: kept, revealAnswers: false).exam.status == .ready)
        #expect(throws: StoreError.self) { try store.confirmExam(id: kept) }
        #expect(throws: StoreError.self) { try store.discardExam(id: kept) }
        _ = try store.startExam(id: kept)

        let dropped = try store.createExam(input, source: "test", status: .draft).id
        try store.discardExam(id: dropped)
        #expect(throws: StoreError.notFound("试卷 \(dropped)")) { try store.examDetail(id: dropped, revealAnswers: false) }
        #expect(try store.exams(stage: 0).map(\.id) == [kept])
        #expect(try store.pool.read { try ExamSection.filter(Column("examId") == dropped).fetchCount($0) } == 0)
        #expect(throws: StoreError.notFound("试卷 \(dropped)")) { try store.confirmExam(id: dropped) }
    }

    @Test func answersHiddenUntilRevealed() throws {
        let store = try makeStore()
        let section = SectionInput(title: "A", weight: 100, source: .problems, problemIds: nil, problems: [problem(), problem(prompt: "二")])
        let id = try store.createExam(ExamInput(stageIndex: 0, kind: .weeklyQuiz, title: "T", timeLimitMinutes: 20, sections: [section]), source: "test").id
        let hidden = try store.examDetail(id: id, revealAnswers: false)
        let hiddenProblems = hidden.sections.flatMap(\.problems)
        #expect(hiddenProblems.count == 2)
        #expect(hiddenProblems.allSatisfy { $0.referenceAnswer == "" && $0.rubric == "" })
        let shown = try store.examDetail(id: id, revealAnswers: true).sections.flatMap(\.problems)
        #expect(shown.allSatisfy { $0.referenceAnswer == "答案" && $0.rubric == "评分标准" })
    }

    @Test func reviewClearedAwardsOnce() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let today = clock.today()
        try store.pool.write { db in
            try db.execute(sql: "DELETE FROM card")  // 清掉种子卡，只留下面两张到期卡
            for i in 0..<2 {
                var c = Card(stageIndex: 0, front: "f\(i)", back: "b", tags: [], step: 0, dueDay: today, createdAt: t0)
                try c.insert(db)
            }
        }
        let due = try store.reviewQueue().cards
        #expect(due.count == 2)
        try store.recordReview(cardId: due[0].id!, remembered: true)
        #expect(try store.xp(on: today) == 0)
        try store.recordReview(cardId: due[1].id!, remembered: false)
        #expect(try store.xp(on: today) == 20)

        let newId = try store.createCards([CardInput(stageIndex: 0, moduleKey: nil, front: "n", back: "b", tags: nil)], source: "test")[0]
        try store.recordReview(cardId: newId, remembered: true)
        #expect(try store.xp(on: today) == 20)
    }

    @Test func newCardLimitIsPerDay() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let today = clock.today()
        try store.pool.write { try $0.execute(sql: "DELETE FROM card") }
        _ = try store.createCards((0..<25).map { CardInput(stageIndex: 0, moduleKey: nil, front: "f\($0)", back: "b", tags: nil) }, source: "test")
        #expect(try store.reviewQueue().cards.count == 20)
        for _ in 0..<20 {
            let next = try #require(store.reviewQueue().cards.first)
            try store.recordReview(cardId: next.id!, remembered: true)
        }
        let after = try store.reviewQueue()
        #expect(after.cards.isEmpty && after.deferred == 0)
        #expect(try store.xp(on: today) == 20)

        clock.current = t0.addingTimeInterval(24 * 3600)
        let tomorrow = try store.reviewQueue()
        #expect(tomorrow.cards.count == 25 && tomorrow.deferred == 0)
        #expect(tomorrow.cards.filter { $0.step == nil }.count == 5)
        #expect(tomorrow.cards.filter { $0.step != nil }.count == 20)
    }

    @Test func invalidCreateThrowsReadableError() throws {
        let store = try makeStore()
        do {
            _ = try store.createProblems([problem(prompt: "  ")], source: "test")
            Issue.record("应当抛错")
        } catch let StoreError.invalid(message) {
            #expect(message.contains("题干"))
        }
    }

    @Test func settingsDefaultsAndOverride() throws {
        let store = try makeStore()
        #expect(try store.setting(.dailyNewCardLimit) == "20")
        #expect(try store.setting(.gradingProviderId) == "")
        try store.setSetting(.assignmentSize, "8")
        #expect(try store.setting(.assignmentSize) == "8")
    }

    @Test func assignmentWithInlineProblems() throws {
        let store = try makeStore()
        let id = try store.createAssignment(
            AssignmentInput(stageIndex: 0, moduleKey: nil, title: "作业", problemIds: nil, problems: [problem(), problem(prompt: "二")]),
            source: "test")
        let a = try #require(store.assignments(day: store.clock.today()).first)
        #expect(a.id == id && a.problemIds.count == 2)
        #expect(try store.problems(ids: a.problemIds).count == 2)
        #expect(try store.openAssignments().count == 1)
    }
}
