import Foundation
@testable import HiveCore
import HiveKit
import Testing

/// In New York's time zone, whose clocks went forward at 2:00 on 8 March 2026 and back at 2:00 on 1 November 2026.
struct ScheduleCalendarTests {
    private let schedule = ScheduleCalendar(calendar: APIFixture.calendar)

    /// A moment written with its offset from UTC, which tells apart the two passes of a repeated hour.
    private func date(_ text: String) throws -> Date {
        try Date(text, strategy: .iso8601)
    }

    private func times(_ times: (Int, Int)...) -> [TimeOfDay] {
        times.map { TimeOfDay(hour: $0.0, minute: $0.1) }
    }

    @Test("The next run is the first of the job's times after now, later today or tomorrow", arguments: [
        ("2027-01-15T03:00:00-05:00", "2027-01-15T14:00:00-05:00"),
        ("2027-01-15T02:30:00-05:00", "2027-01-15T14:00:00-05:00"),
        ("2027-01-15T14:00:00-05:00", "2027-01-16T02:30:00-05:00"),
        ("2027-01-15T23:59:00-05:00", "2027-01-16T02:30:00-05:00"),
        ("2027-01-15T00:00:00-05:00", "2027-01-15T02:30:00-05:00"),
    ])
    func nextTime(after: String, expected: String) throws {
        // Act
        let next = schedule.nextRun(after: try date(after), times: times((2, 30), (14, 0)))

        // Assert
        #expect(next == (try date(expected)))
    }

    @Test("Midnight comes on the next day, across the ends of months and years, and a leap day", arguments: [
        ("2026-01-31T23:00:00-05:00", "2026-02-01T00:00:00-05:00"),
        ("2026-02-28T12:00:00-05:00", "2026-03-01T00:00:00-05:00"),
        ("2028-02-28T12:00:00-05:00", "2028-02-29T00:00:00-05:00"),
        ("2026-04-30T23:59:00-04:00", "2026-05-01T00:00:00-04:00"),
        ("2026-12-31T23:59:00-05:00", "2027-01-01T00:00:00-05:00"),
    ])
    func monthEnds(after: String, expected: String) throws {
        // Act
        let next = schedule.nextRun(after: try date(after), times: times((0, 0)))

        // Assert
        #expect(next == (try date(expected)))
    }

    @Test("A time the clocks skip going forward runs at the first moment after the gap, and at its own time the next day")
    func springForward() throws {
        // Arrange
        let before = try date("2026-03-07T12:00:00-05:00")

        // Act
        let first = try #require(schedule.nextRun(after: before, times: times((2, 30))))
        let second = schedule.nextRun(after: first, times: times((2, 30)))

        // Assert
        #expect(first == (try date("2026-03-08T03:00:00-04:00")))
        #expect(second == (try date("2026-03-09T02:30:00-04:00")))
    }

    @Test("The day the clocks go forward keeps its other times at their own local time")
    func springForwardOtherTimes() throws {
        // Act
        let next = schedule.nextRun(after: try date("2026-03-08T00:00:00-05:00"), times: times((0, 0), (12, 0)))

        // Assert
        #expect(next == (try date("2026-03-08T12:00:00-04:00")))
    }

    @Test("A time the clocks repeat going back runs once, on its first pass")
    func fallBack() throws {
        // Arrange
        let before = try date("2026-10-31T12:00:00-04:00")

        // Act
        let first = try #require(schedule.nextRun(after: before, times: times((1, 30))))
        let second = schedule.nextRun(after: first, times: times((1, 30)))

        // Assert
        #expect(first == (try date("2026-11-01T01:30:00-04:00")))
        #expect(second == (try date("2026-11-02T01:30:00-05:00")))
    }

    @Test("Hourly times stay an hour apart in local time across the repeated hour")
    func fallBackHourly() throws {
        // Arrange
        let hourly = (0 ..< 24).map { TimeOfDay(hour: $0, minute: 0) }
        var runs: [Date] = []
        var after = try date("2026-11-01T00:30:00-04:00")

        // Act
        for _ in 0 ..< 3 {
            let next = try #require(schedule.nextRun(after: after, times: hourly))
            runs.append(next)
            after = next
        }

        // Assert
        #expect(runs == [
            try date("2026-11-01T01:00:00-04:00"),
            try date("2026-11-01T02:00:00-05:00"),
            try date("2026-11-01T03:00:00-05:00"),
        ])
    }

    @Test("A job with no times has no next run")
    func noTimes() throws {
        // Act
        let next = schedule.nextRun(after: try date("2027-01-15T03:00:00-05:00"), times: [])

        // Assert
        #expect(next == nil)
    }

    @Test("The key changes with the times or the time zone, and not with their order")
    func key() {
        // Arrange
        var tokyo = APIFixture.calendar
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt

        // Act
        let key = schedule.key(for: times((2, 30), (14, 0)))

        // Assert
        #expect(key == schedule.key(for: times((14, 0), (2, 30))))
        #expect(key != schedule.key(for: times((2, 30))))
        #expect(key != ScheduleCalendar(calendar: tokyo).key(for: times((2, 30), (14, 0))))
    }
}
