import Foundation
import GRDB
import Testing
@testable import StudyCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func makeStore(clock: FixedClock = FixedClock(t0), notifier: ChangeNotifier = NoopChangeNotifier()) throws -> StudyStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
    return try StudyStore(database: AppDatabase(url: dir.appendingPathComponent("test.sqlite")), clock: clock, notifier: notifier)
}

private final class CountingNotifier: ChangeNotifier, @unchecked Sendable {
    var count = 0
    func post() { count += 1 }
}

private func day(_ raw: String) -> Day { Day(rawValue: raw)! }

@Suite struct XPTests {
    @Test func problemXPScalesWithScore() {
        #expect(XPRules.problemXP(difficulty: .hard, score: 10, max: 10) == 60)
        #expect(XPRules.problemXP(difficulty: .medium, score: 5, max: 10) == 13)
        #expect(XPRules.problemXP(difficulty: .easy, score: 0, max: 10) == 0)
    }

    @Test func levelCurve() {
        #expect(XPRules.level(forXP: 0) == 1)
        #expect(XPRules.level(forXP: 99) == 1)
        #expect(XPRules.level(forXP: 100) == 2)
        #expect(XPRules.level(forXP: 300) == 3)
        #expect(XPRules.level(forXP: 4500) == 10)
        #expect(XPRules.xpForNextLevel(1) == 100)
        #expect(XPRules.xpForNextLevel(2) == 300)
    }

    @Test func streakCountsBackFromToday() {
        let cal = Calendar(identifier: .gregorian)
        let days: Set<Day> = [day("2026-11-23"), day("2026-11-24"), day("2026-11-25")]
        #expect(XPRules.streak(studyDays: days, today: day("2026-11-25"), calendar: cal) == 3)
        #expect(XPRules.streak(studyDays: days, today: day("2026-11-26"), calendar: cal) == 3)
        #expect(XPRules.streak(studyDays: days, today: day("2026-11-27"), calendar: cal) == 0)
    }

    @Test func awardIsIdempotent() throws {
        let notifier = CountingNotifier()
        let store = try makeStore(notifier: notifier)
        let d = day("2026-11-25")
        #expect(try store.awardXP(dedupKey: "k", amount: 50, reason: .assignmentCompleted, day: d))
        #expect(try store.awardXP(dedupKey: "k", amount: 50, reason: .assignmentCompleted, day: d) == false)
        #expect(try store.totalXP() == 50)
        #expect(try store.xp(on: d) == 50)
        #expect(notifier.count == 1)
    }

    @Test func studyDaysOnlyCountsReviewAndAssignment() throws {
        let store = try makeStore()
        try store.awardXP(dedupKey: "a", amount: 50, reason: .assignmentCompleted, day: day("2026-11-24"))
        try store.awardXP(dedupKey: "b", amount: 20, reason: .reviewCleared, day: day("2026-11-25"))
        try store.awardXP(dedupKey: "c", amount: 5, reason: .dailyNote, day: day("2026-11-23"))
        #expect(try store.studyDays() == [day("2026-11-24"), day("2026-11-25")])
    }

    @Test func dailyNoteAwardsOnce() throws {
        let store = try makeStore()
        try store.saveDailyNote("第一次")
        try store.saveDailyNote("第二次")
        #expect(try store.totalXP() == 5)
        let text = try store.pool.read { try DailyNote.fetchOne($0, key: store.clock.today().rawValue)?.text }
        #expect(text == "第二次")
    }

    @Test func progressSummaryReflectsState() throws {
        let store = try makeStore()
        let today = store.clock.today()
        try store.awardXP(dedupKey: "a", amount: 120, reason: .assignmentCompleted, day: today)
        let s = try store.progressSummary()
        #expect(s.xp == 120)
        #expect(s.level == 2)
        #expect(s.nextLevelXP == 300)
        #expect(s.xpToday == 120)
        #expect(s.streak == 1)
        #expect(s.stageStatuses.count == 10)
        #expect(s.stageStatuses[s.currentStage] == .inProgress)
    }
}
