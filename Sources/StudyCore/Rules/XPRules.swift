import Foundation

/// 经验值、等级曲线与连续学习天数。
public enum XPRules {
    public static let assignmentCompleted = 50
    public static let reviewCleared = 20
    public static let weeklyPassed = 100
    public static let stagePassed = 500
    public static let dailyNote = 5

    /// 基数（简单 10 / 中等 25 / 困难 60）× 得分比例，四舍五入。
    public static func problemXP(difficulty: Difficulty, score: Double, max: Double) -> Int {
        guard max > 0 else { return 0 }
        let base: Double
        switch difficulty {
        case .easy: base = 10
        case .medium: base = 25
        case .hard: base = 60
        }
        let ratio = Swift.min(Swift.max(score / max, 0), 1)
        return Int((base * ratio).rounded())
    }

    /// 等级 L 的门槛 = 50·L·(L−1)，从 1 级起。
    public static func level(forXP xp: Int) -> Int {
        var level = 1
        while xp >= xpForNextLevel(level) { level += 1 }
        return level
    }

    /// 升到 level+1 所需的累计经验值。
    public static func xpForNextLevel(_ level: Int) -> Int { 50 * (level + 1) * level }

    /// 从今天往前连续的学习天数；今天还没学则从昨天起算。
    public static func streak(studyDays: Set<Day>, today: Day, calendar: Calendar) -> Int {
        var cursor = studyDays.contains(today) ? today : today.adding(days: -1, calendar: calendar)
        var count = 0
        while studyDays.contains(cursor) {
            count += 1
            cursor = cursor.adding(days: -1, calendar: calendar)
        }
        return count
    }
}
