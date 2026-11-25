import Testing
import Foundation
@testable import StudyCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return c
}()
private let today = Day(rawValue: "2026-11-25")!

private func card(_ i: Int, step: Int?, due: Day) -> Card {
    Card(id: Int64(i), stageIndex: 0, front: "f\(i)", back: "b", tags: [], step: step, dueDay: due, createdAt: Date(timeIntervalSince1970: 0))
}

@Suite struct ReviewSchedulerTests {
    @Test func newCardRememberedDueTomorrow() {
        let r = ReviewScheduler.nextCard(step: nil, remembered: true, today: today, calendar: cal)
        #expect(r.step == 0)
        #expect(r.due == Day(rawValue: "2026-11-26")!)
    }

    @Test func ladderProgression() {
        let cases: [(Int, Int, Int)] = [(0, 1, 2), (4, 5, 30), (5, 6, 60), (7, 8, 60)]
        for (from, to, interval) in cases {
            let r = ReviewScheduler.nextCard(step: from, remembered: true, today: today, calendar: cal)
            #expect(r.step == to)
            #expect(r.due == today.adding(days: interval, calendar: cal))
        }
    }

    @Test func forgetResetsToOneDay() {
        let r = ReviewScheduler.nextCard(step: 4, remembered: false, today: today, calendar: cal)
        #expect(r.step == 0)
        #expect(r.due == today.adding(days: 1, calendar: cal))
    }

    @Test func mistakeGraduatesAfterTwoCorrect() {
        let a = ReviewScheduler.nextMistake(step: 0, streak: 0, correct: true, today: today, calendar: cal)
        #expect(a.step == 1)
        #expect(a.streak == 1)
        #expect(a.due == today.adding(days: 3, calendar: cal))
        #expect(a.graduated == false)
        let b = ReviewScheduler.nextMistake(step: a.step, streak: a.streak, correct: true, today: today, calendar: cal)
        #expect(b.graduated == true)
    }

    @Test func mistakeWrongResets() {
        let r = ReviewScheduler.nextMistake(step: 2, streak: 1, correct: false, today: today, calendar: cal)
        #expect(r.step == 0)
        #expect(r.streak == 0)
        #expect(r.due == today.adding(days: 1, calendar: cal))
        #expect(r.graduated == false)
    }

    @Test func correctThresholdIs80Percent() {
        #expect(ReviewScheduler.isCorrect(score: 8, max: 10))
        #expect(!ReviewScheduler.isCorrect(score: 7.9, max: 10))
    }

    @Test func queueCapsAndDefers() {
        // 到期卡 dueDay 递增：id 1 最逾期
        let due = (1...120).map { card($0, step: 0, due: today.adding(days: -200 + $0, calendar: cal)) }
        let new = (1001...1030).map { card($0, step: nil, due: today) }
        let shuffled = Array(due.reversed())
        let q = ReviewScheduler.queue(due: shuffled, new: new, newLimit: 20, displayCap: 100, today: today)
        #expect(q.cards.count == 100)
        #expect(q.cards.allSatisfy { $0.step != nil })
        #expect(q.cards.first?.id == 1)
        #expect(q.deferred == 40)
    }
}
