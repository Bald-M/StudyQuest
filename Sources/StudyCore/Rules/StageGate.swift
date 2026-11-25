import Foundation

public struct StageExamRecord: Sendable {
    public var day: Day
    public var passed: Bool
    public var weakestModuleId: Int64?
    public init(day: Day, passed: Bool, weakestModuleId: Int64?) {
        self.day = day; self.passed = passed; self.weakestModuleId = weakestModuleId
    }
}

public enum StageGateStatus: Equatable {
    case open
    case coolingDown(until: Day)
    case needsRelearn(moduleId: Int64)
    case locked
    case alreadyPassed
}

public enum StageGate {
    /// `history` 按时间升序。冷却先于重学判断；冷却截止日当天已可考试。
    public static func status(stage: Stage, history: [StageExamRecord], relearnSatisfied: Bool, today: Day, calendar: Calendar) -> StageGateStatus {
        switch stage.status {
        case .locked: return .locked
        case .passed: return .alreadyPassed
        case .inProgress: break
        }
        guard let last = history.last, !last.passed else { return .open }
        let until = last.day.adding(days: stage.cooldownDays, calendar: calendar)
        if today < until { return .coolingDown(until: until) }
        if history.count >= 2, !history[history.count - 2].passed, !relearnSatisfied, let moduleId = last.weakestModuleId {
            return .needsRelearn(moduleId: moduleId)
        }
        return .open
    }
}
