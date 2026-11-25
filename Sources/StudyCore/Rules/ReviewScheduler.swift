import Foundation

/// 卡片与错题的间隔复习排期，以及每日复习队列。纯逻辑，不访问数据库。
public enum ReviewScheduler {
    public static let cardLadder = [1, 2, 4, 7, 15, 30]
    public static let longTermInterval = 60
    public static let mistakeLadder = [1, 3, 7, 14]

    public static func nextCard(step: Int?, remembered: Bool, today: Day, calendar: Calendar) -> (step: Int, due: Day) {
        guard remembered else { return (0, today.adding(days: 1, calendar: calendar)) }
        let newStep = (step ?? -1) + 1
        let interval = newStep < cardLadder.count ? cardLadder[newStep] : longTermInterval
        return (newStep, today.adding(days: interval, calendar: calendar))
    }

    public static func nextMistake(step: Int, streak: Int, correct: Bool, today: Day, calendar: Calendar) -> (step: Int, streak: Int, due: Day, graduated: Bool) {
        guard correct else { return (0, 0, today.adding(days: 1, calendar: calendar), false) }
        let newStreak = streak + 1
        let newStep = step + 1
        let interval = mistakeLadder[min(newStep, mistakeLadder.count - 1)]
        return (newStep, newStreak, today.adding(days: interval, calendar: calendar), newStreak >= 2)
    }

    public static func isCorrect(score: Double, max: Double) -> Bool {
        score >= 0.8 * max
    }

    /// 到期卡按 dueDay 升序（最逾期在前），再接至多 newLimit 张新卡，总数截到 displayCap。
    /// deferred 只统计被 displayCap 截掉的卡；超出 newLimit 的新卡不算顺延。
    public static func queue(due: [Card], new: [Card], newLimit: Int, displayCap: Int, today: Day) -> (cards: [Card], deferred: Int) {
        let sortedDue = due.sorted { ($0.dueDay, $0.id ?? 0) < ($1.dueDay, $1.id ?? 0) }
        let admitted = sortedDue + new.filter { $0.step == nil }.prefix(newLimit)
        let shown = Array(admitted.prefix(displayCap))
        return (shown, admitted.count - shown.count)
    }
}
