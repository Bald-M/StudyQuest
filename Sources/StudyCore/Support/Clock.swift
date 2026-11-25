import Foundation

/// 时间来源。业务代码一律通过注入的 Clock 取"现在"和"今天"。
public protocol Clock: Sendable {
    func now() -> Date
    var calendar: Calendar { get }
}

extension Clock {
    public func today() -> Day { Day.of(now(), calendar: calendar) }
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
    public var calendar: Calendar { Calendar.current }
}

/// 测试用：可手动改变当前时间。放在 StudyCore 以便各测试 target 复用。
public final class FixedClock: Clock, @unchecked Sendable {
    public var current: Date
    public let calendar: Calendar

    public init(_ current: Date, calendar: Calendar = Calendar.current) {
        self.current = current
        self.calendar = calendar
    }

    public func now() -> Date { current }
}
