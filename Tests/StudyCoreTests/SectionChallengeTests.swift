import Foundation
import GRDB
import Testing
@testable import StudyCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func makeStore(clock: FixedClock) throws -> StudyStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
    return try StudyStore(database: AppDatabase(url: dir.appendingPathComponent("test.sqlite")), clock: clock, notifier: NoopChangeNotifier())
}

private func problem(stage: Int, _ i: Int) -> ProblemInput {
    ProblemInput(stageIndex: stage, moduleKey: nil, kind: .shortAnswer, prompt: "题\(i)", options: nil,
                 referenceAnswer: "答案", rubric: "评分标准", maxScore: 10, difficulty: .medium, tags: nil)
}

/// 导入一本两节的教材，返回两节的 id。
private func importBook(_ store: StudyStore, stage: Int = 0) throws -> [Int64] {
    let parsed = ParsedTextbook(title: "教材", sourceKind: .markdownFile,
                                sections: (0..<2).map { ParsedSection(matchKey: "k\($0)", chapterTitle: "章", title: "节\($0)", text: "正文\($0)") },
                                assets: [:], pdfData: nil)
    let id = try store.importTextbook(parsed, stageIndex: stage, sourcePath: "")
    return try store.sectionRows(textbookId: id).map { $0.section.id! }
}

private func makeChallenge(_ store: StudyStore, sectionId: Int64, stage: Int = 0, count: Int = 5) throws -> Int64 {
    try store.createSectionChallenge(
        sectionId: sectionId, problems: (0..<count).map { problem(stage: stage, $0) },
        cards: [CardInput(stageIndex: stage, moduleKey: nil, front: "正", back: "反", tags: nil)], source: "test")
}

private func submitAndGrade(_ store: StudyStore, _ attempt: Attempt, scores: [Double]) throws {
    try store.submit(attemptId: attempt.id!)
    let problems = try store.pendingGrading(attemptId: attempt.id!)
    #expect(problems.count == scores.count)
    for (p, s) in zip(problems, scores) {
        try store.recordGrade(attemptId: attempt.id!, problemId: p.id!, score: s, feedback: "", mistakes: [], grader: "test", raw: "")
    }
}

private func xpKeys(_ store: StudyStore) throws -> [String] {
    try store.pool.read { try String.fetchAll($0, sql: "SELECT dedupKey FROM xpEvent ORDER BY id") }
}

@Suite struct SectionChallengeTests {
    @Test func createStoresProblemsAndCardsLinkedToSection() throws {
        let store = try makeStore(clock: FixedClock(t0))
        let sid = try importBook(store)[0]
        #expect(try store.hasSectionCards(sectionId: sid) == false)
        #expect(try store.challengeNeedsGeneration(sectionId: sid))
        let cid = try makeChallenge(store, sectionId: sid)
        let challenge = try #require(try store.latestChallenge(sectionId: sid))
        #expect(challenge.id == cid)
        #expect(challenge.problemIds.count == 5)
        #expect(try store.problems(ids: challenge.problemIds).allSatisfy { $0.sectionId == sid })
        #expect(try store.hasSectionCards(sectionId: sid))
        #expect(try store.challengeNeedsGeneration(sectionId: sid) == false)
        #expect(throws: StoreError.notFound("章节 9999")) {
            try store.createSectionChallenge(sectionId: 9999, problems: [problem(stage: 0, 0)], cards: [], source: "test")
        }
        #expect(throws: StoreError.self) {
            try store.createSectionChallenge(sectionId: sid, problems: [], cards: [], source: "test")
        }
        #expect(throws: StoreError.self) {
            try store.createSectionChallenge(sectionId: sid, problems: [problem(stage: 99, 0)], cards: [], source: "test")
        }
        // 校验失败不留下任何半截数据
        #expect(try store.pool.read { try SectionChallenge.fetchCount($0) } == 1)
    }

    @Test func passingMastersAndAwardsXPOnce() throws {
        let store = try makeStore(clock: FixedClock(t0))
        let sids = try importBook(store)
        let cid = try makeChallenge(store, sectionId: sids[0])
        let attempt = try store.startSectionChallenge(challengeId: cid)
        #expect(attempt.kind == .section)
        #expect(try store.startSectionChallenge(challengeId: cid).id == attempt.id)
        try submitAndGrade(store, attempt, scores: [8, 8, 8, 8, 8])
        let graded = try store.attemptDetail(id: attempt.id!).attempt
        #expect(graded.passed == true)
        #expect(graded.totalPercent == 80)
        #expect(try store.section(id: sids[0]).masteredAt == t0)
        let keys = try xpKeys(store)
        #expect(keys.filter { $0 == "section:\(sids[0])" }.count == 1)
        #expect(!keys.contains { $0.hasPrefix("problem:") })
        let expected = 5 * XPRules.problemXP(difficulty: .medium, score: 8, max: 10)
        #expect(try store.totalXP() == expected)
        let bookId = try store.section(id: sids[0]).textbookId
        #expect(try store.sectionRows(textbookId: bookId).map(\.state) == [.mastered, .unlocked])
    }

    @Test func failingDoesNotMasterButRecordsMistakesAndStudyDay() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let sid = try importBook(store)[0]
        let cid = try makeChallenge(store, sectionId: sid)
        let attempt = try store.startSectionChallenge(challengeId: cid)
        try submitAndGrade(store, attempt, scores: [0, 0, 0, 0, 0])
        #expect(try store.attemptDetail(id: attempt.id!).attempt.passed == false)
        #expect(try store.section(id: sid).masteredAt == nil)
        #expect(!(try xpKeys(store)).contains { $0.hasPrefix("section:") })
        let challenge = try #require(try store.latestChallenge(sectionId: sid))
        #expect(Set(try store.mistakes(includeGraduated: true).map(\.problemId)) == Set(challenge.problemIds))
        #expect(try store.studyDays().contains(clock.today()))
    }

    @Test func replayAfterMasteryReusesChallengeAndGivesNoXP() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let sid = try importBook(store)[0]
        let cid = try makeChallenge(store, sectionId: sid)
        try submitAndGrade(store, try store.startSectionChallenge(challengeId: cid), scores: [10, 10, 10, 10, 10])
        #expect(try store.challengeNeedsGeneration(sectionId: sid) == false)
        let xp = try store.totalXP()
        clock.current = t0.addingTimeInterval(3600)
        let replay = try store.startSectionChallenge(challengeId: cid)
        try submitAndGrade(store, replay, scores: [10, 10, 10, 10, 10])
        #expect(try store.attemptDetail(id: replay.id!).attempt.passed == true)
        #expect(try store.totalXP() == xp)
        #expect(try store.section(id: sid).masteredAt == t0)
        #expect(try store.challengeNeedsGeneration(sectionId: sid) == false)
    }

    @Test func failedLastAttemptNeedsNewChallenge() throws {
        let store = try makeStore(clock: FixedClock(t0))
        let sid = try importBook(store)[0]
        let cid = try makeChallenge(store, sectionId: sid)
        let attempt = try store.startSectionChallenge(challengeId: cid)
        // 未判完的作答：复用
        #expect(try store.challengeNeedsGeneration(sectionId: sid) == false)
        try submitAndGrade(store, attempt, scores: [0, 0, 0, 0, 0])
        #expect(try store.challengeNeedsGeneration(sectionId: sid))
        // 新闯关生成后，最新闯关没有作答：不再需要生成
        _ = try makeChallenge(store, sectionId: sid)
        #expect(try store.challengeNeedsGeneration(sectionId: sid) == false)
        // 闯关全部过期后需要生成，且过期的闯关不能开始
        try store.pool.write { try $0.execute(sql: "UPDATE sectionChallenge SET stale = 1") }
        #expect(try store.latestChallenge(sectionId: sid) == nil)
        #expect(try store.challengeNeedsGeneration(sectionId: sid))
        #expect(throws: StoreError.invalid("本节内容已更新，请重新闯关")) { try store.startSectionChallenge(challengeId: cid) }
    }

    @Test func lockedStageBlocksStart() throws {
        let store = try makeStore(clock: FixedClock(t0))
        let sid = try importBook(store, stage: 1)[0]
        let cid = try makeChallenge(store, sectionId: sid, stage: 1)
        #expect(throws: StoreError.blocked("该阶段尚未解锁，可以先阅读，解锁后再闯关")) { try store.startSectionChallenge(challengeId: cid) }
        #expect(throws: StoreError.notFound("闯关 9999")) { try store.startSectionChallenge(challengeId: 9999) }
    }

    @Test func refinalizeIsIdempotent() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let sid = try importBook(store)[0]
        let cid = try makeChallenge(store, sectionId: sid)
        let attempt = try store.startSectionChallenge(challengeId: cid)
        try submitAndGrade(store, attempt, scores: [10, 10, 10, 10, 0])
        #expect(try store.section(id: sid).masteredAt == t0)
        let xp = try store.totalXP()
        let mistakes = try store.mistakes(includeGraduated: true).count
        #expect(mistakes == 1)

        clock.current = t0.addingTimeInterval(60)
        let first = try #require(try store.attemptDetail(id: attempt.id!).items.first).problem.id!
        try store.recordGrade(attemptId: attempt.id!, problemId: first, score: 9, feedback: "复判", mistakes: [], grader: "test", raw: "")
        try store.finalize(attemptId: attempt.id!)
        #expect(try store.totalXP() == xp)
        #expect(try store.mistakes(includeGraduated: true).count == mistakes)
        #expect(try store.section(id: sid).masteredAt == t0)
        #expect(try xpKeys(store).filter { $0.hasPrefix("section:") }.count == 1)
    }
}
