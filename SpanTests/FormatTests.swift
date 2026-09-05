import Foundation
import Testing
@testable import Span

@Suite("Format")
struct FormatTests {

    // MARK: - clock

    @Test("clock shows mm:ss below an hour", arguments: [
        (TimeInterval(0), "00:00"),
        (1, "00:01"),
        (59, "00:59"),
        (60, "01:00"),
        (599, "09:59"),
        (3599, "59:59"),
    ])
    func clockBelowAnHour(duration: TimeInterval, expected: String) {
        #expect(Format.clock(duration) == expected)
    }

    @Test("clock adds an hours component at and above an hour", arguments: [
        (TimeInterval(3600), "1:00:00"),
        (3661, "1:01:01"),
        (7322, "2:02:02"),
        (86_399, "23:59:59"),
    ])
    func clockAboveAnHour(duration: TimeInterval, expected: String) {
        #expect(Format.clock(duration) == expected)
    }

    @Test("clock floors a negative duration at zero")
    func clockNegative() {
        #expect(Format.clock(-1) == "00:00")
        #expect(Format.clock(-3600) == "00:00")
    }

    @Test("clock rounds rather than truncates")
    func clockRounds() {
        #expect(Format.clock(59.6) == "01:00")
        #expect(Format.clock(59.4) == "00:59")
    }

    // MARK: - compact

    @Test("compact distinguishes nothing from not-quite-a-minute")
    func compactSubMinute() {
        #expect(Format.compact(0) == "0m")
        #expect(Format.compact(1) == "< 1m")
        #expect(Format.compact(59) == "< 1m")
    }

    @Test("compact renders minutes, hours and both", arguments: [
        (TimeInterval(60), "1m"),
        (90, "1m"),
        (3540, "59m"),
        (3600, "1h"),
        (3660, "1h 1m"),
        (5400, "1h 30m"),
        (7200, "2h"),
        (45_000, "12h 30m"),
    ])
    func compactSpans(duration: TimeInterval, expected: String) {
        #expect(Format.compact(duration) == expected)
    }

    @Test("compact treats a negative duration as none")
    func compactNegative() {
        #expect(Format.compact(-600) == "0m")
    }

    // MARK: - percent

    @Test("percent", arguments: [
        (0.0, "0%"),
        (-0.5, "0%"),
        (0.001, "< 1%"),
        (0.009, "< 1%"),
        (0.01, "1%"),
        (0.5, "50%"),
        (0.994, "99%"),
        (1.0, "100%"),
        (1.5, "150%"),
    ])
    func percent(fraction: Double, expected: String) {
        #expect(Format.percent(fraction) == expected)
    }

    // MARK: - dayTitle

    @Test("dayTitle names the three days around the reference")
    func dayTitleRelative() {
        let reference = Clock.date(2025, 9, 3, 14, 30)
        #expect(Format.dayTitle(Clock.date(2025, 9, 3, 0, 1), relativeTo: reference) == "Today")
        #expect(Format.dayTitle(Clock.date(2025, 9, 2, 23, 59), relativeTo: reference) == "Yesterday")
        #expect(Format.dayTitle(Clock.date(2025, 9, 4, 6, 0), relativeTo: reference) == "Tomorrow")
    }

    @Test("dayTitle falls back to a dated label further out")
    func dayTitleAbsolute() {
        let reference = Clock.date(2025, 9, 3)
        #expect(Format.dayTitle(Clock.date(2025, 9, 5), relativeTo: reference) == "Fri, Sep 5")
        #expect(Format.dayTitle(Clock.date(2025, 8, 31), relativeTo: reference) == "Sun, Aug 31")
    }

    @Test("dayTitle handles a month boundary")
    func dayTitleAcrossMonths() {
        let reference = Clock.date(2025, 10, 1, 9, 0)
        #expect(Format.dayTitle(Clock.date(2025, 9, 30, 9, 0), relativeTo: reference) == "Yesterday")
    }

    @Test("dayTitle handles a year boundary")
    func dayTitleAcrossYears() {
        let reference = Clock.date(2026, 1, 1, 9, 0)
        #expect(Format.dayTitle(Clock.date(2025, 12, 31, 9, 0), relativeTo: reference) == "Yesterday")
    }

    // MARK: - greeting

    @Test("greeting splits the day at noon and six", arguments: [
        (0, "Good morning"),
        (6, "Good morning"),
        (11, "Good morning"),
        (12, "Good afternoon"),
        (17, "Good afternoon"),
        (18, "Good evening"),
        (23, "Good evening"),
    ])
    func greetingByHour(hour: Int, expected: String) {
        let at = Clock.date(2025, 9, 3, hour, 30)
        #expect(Format.greeting("", at: at) == expected)
    }

    @Test("greeting appends a name when there is one")
    func greetingWithName() {
        let morning = Clock.date(2025, 9, 3, 9, 0)
        #expect(Format.greeting("Amey", at: morning) == "Good morning, Amey")
        #expect(Format.greeting("  Amey  ", at: morning) == "Good morning, Amey")
        #expect(Format.greeting("   ", at: morning) == "Good morning")
    }

    // MARK: - weekdayInitial / hourLabel / timeOfDay

    @Test("weekdayInitial takes the first letter of the weekday")
    func weekdayInitial() {
        #expect(Format.weekdayInitial(Clock.date(2025, 9, 1)) == "M")
        #expect(Format.weekdayInitial(Clock.date(2025, 9, 3)) == "W")
        #expect(Format.weekdayInitial(Clock.date(2025, 9, 5)) == "F")
    }

    @Test("hourLabel renders a 12-hour gutter label", arguments: [
        (0, "12 AM"), (1, "1 AM"), (9, "9 AM"), (12, "12 PM"), (13, "1 PM"), (23, "11 PM"),
    ])
    func hourLabel(hour: Int, expected: String) {
        #expect(Format.hourLabel(hour).normalisingSpaces == expected)
    }

    @Test("timeOfDay renders a short local time")
    func timeOfDay() {
        #expect(Format.timeOfDay(Clock.date(2025, 9, 3, 9, 41)).normalisingSpaces == "9:41 AM")
        #expect(Format.timeOfDay(Clock.date(2025, 9, 3, 0, 5)).normalisingSpaces == "12:05 AM")
        #expect(Format.timeOfDay(Clock.date(2025, 9, 3, 13, 0)).normalisingSpaces == "1:00 PM")
    }
}
