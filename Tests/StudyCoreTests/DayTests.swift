import Foundation
import Testing
@testable import StudyCore

private func shanghai() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return cal
}

@Test func addingCrossesMonth() {
    let cal = shanghai()
    #expect(Day(rawValue: "2026-11-30")!.adding(days: 1, calendar: cal) == Day(rawValue: "2026-12-01")!)
}

@Test func distanceIsSigned() {
    let cal = shanghai()
    let a = Day(rawValue: "2026-11-25")!
    let b = Day(rawValue: "2026-11-28")!
    #expect(a.distance(to: b, calendar: cal) == 3)
    #expect(b.distance(to: a, calendar: cal) == -3)
}

@Test func ofUsesLocalCalendar() {
    let date = ISO8601DateFormatter().date(from: "2026-11-25T16:30:00Z")!
    #expect(Day.of(date, calendar: shanghai()).rawValue == "2026-11-26")
}

@Test func sundayAndWeekStart() {
    let cal = shanghai()
    let sunday = Day(rawValue: "2026-11-29")!
    #expect(sunday.isSunday(calendar: cal))
    #expect(sunday.startOfWeek(calendar: cal) == Day(rawValue: "2026-11-23")!)
}

@Test func invalidRawValueIsRejected() {
    #expect(Day(rawValue: "2026-13-40") == nil)
    #expect(Day(rawValue: "hello") == nil)
}

@Test func fixedClockProvidesToday() {
    let date = ISO8601DateFormatter().date(from: "2026-11-25T16:30:00Z")!
    let clock = FixedClock(date, calendar: shanghai())
    #expect(clock.today().rawValue == "2026-11-26")
}
