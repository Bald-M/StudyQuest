import Foundation

/// 本地自然日，格式 "yyyy-MM-dd"。所有"按天"逻辑统一使用它。
public struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard Day.parts(of: rawValue) != nil else { return nil }
        self.rawValue = rawValue
    }

    public static func of(_ date: Date, calendar: Calendar) -> Day {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return Day(rawValue: String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!))!
    }

    public func adding(days: Int, calendar: Calendar) -> Day {
        Day.of(calendar.date(byAdding: .day, value: days, to: startDate(calendar: calendar))!, calendar: calendar)
    }

    /// 从 self 到 other 的天数，other 在后为正。
    public func distance(to other: Day, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: startDate(calendar: calendar), to: other.startDate(calendar: calendar)).day!
    }

    public func isSunday(calendar: Calendar) -> Bool {
        calendar.component(.weekday, from: startDate(calendar: calendar)) == 1
    }

    /// 所在周的周一（周一为一周开始）。
    public func startOfWeek(calendar: Calendar) -> Day {
        let weekday = calendar.component(.weekday, from: startDate(calendar: calendar)) // 1 = 周日
        return adding(days: -((weekday + 5) % 7), calendar: calendar)
    }

    public static func < (lhs: Day, rhs: Day) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String { rawValue }

    // MARK: Codable（以字符串存储，并校验格式）

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let day = Day(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "非法日期: \(raw)"))
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    // MARK: 内部

    private func startDate(calendar: Calendar) -> Date {
        let p = Day.parts(of: rawValue)!
        return calendar.date(from: DateComponents(year: p.0, month: p.1, day: p.2))!
    }

    /// 严格解析 "yyyy-MM-dd"，并校验是真实存在的日期。
    private static func parts(of raw: String) -> (Int, Int, Int)? {
        let pieces = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
              let y = Int(pieces[0]), let m = Int(pieces[1]), let d = Int(pieces[2]) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let date = utc.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
        let c = utc.dateComponents([.year, .month, .day], from: date)
        guard c.year == y, c.month == m, c.day == d else { return nil }
        return (y, m, d)
    }
}
