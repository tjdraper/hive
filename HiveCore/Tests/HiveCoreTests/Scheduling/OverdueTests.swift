import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct OverdueTests {
    private let schedule = ScheduleCalendar(calendar: APIFixture.calendar)
    private let midnight = [TimeOfDay(hour: 0, minute: 0)]

    private func date(_ text: String) throws -> Date {
        try Date(text, strategy: .iso8601)
    }

    /// Measured from the last snapshot, or when the job was added if there's none.
    private func overdueSince(lastSnapshotAt: String?, isRunning: Bool = false, now: String) throws -> Date? {
        let since = try date(lastSnapshotAt ?? "2027-01-01T12:00:00-05:00")
        return OverdueCheck(schedule: schedule).overdueSince(since, times: midnight, isRunning: isRunning, now: try date(now))
    }

    @Test("A daily job becomes overdue a few hours after its next time passes without a snapshot", arguments: [
        ("2027-01-12T02:59:59-05:00", false),
        ("2027-01-12T03:00:00-05:00", true),
        ("2027-01-14T12:00:00-05:00", true),
    ])
    func dailyJob(now: String, overdue: Bool) throws {
        // Act
        let since = try overdueSince(lastSnapshotAt: "2027-01-11T00:20:00-05:00", now: now)

        // Assert
        #expect(since == (overdue ? try date("2027-01-12T03:00:00-05:00") : nil))
    }

    @Test("A job that has never made a snapshot is measured from when it was added")
    func neverRun() throws {
        // Act
        let before = try overdueSince(lastSnapshotAt: nil, now: "2027-01-02T02:59:00-05:00")
        let after = try overdueSince(lastSnapshotAt: nil, now: "2027-01-02T03:00:00-05:00")

        // Assert
        #expect(before == nil)
        #expect(after == (try date("2027-01-02T03:00:00-05:00")))
    }

    @Test("A job isn't overdue while it runs")
    func notWhileRunning() throws {
        // Act
        let since = try overdueSince(lastSnapshotAt: "2027-01-11T00:20:00-05:00", isRunning: true, now: "2027-01-14T12:00:00-05:00")

        // Assert
        #expect(since == nil)
    }

    @Test("A job is marked overdue when its time passes without a snapshot, and no longer once a run succeeds")
    func clearedBySuccess() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        let notYet = try await fixture.status().overdueSince
        fixture.clock.advance(by: 14 * 60 * 60)

        // Act
        let overdue = try await fixture.status().overdueSince
        _ = try await fixture.run()
        let afterSuccess = try await fixture.status()

        // Assert
        #expect(notYet == nil)
        #expect(overdue == (try date("2027-01-15T17:00:00-05:00")))
        #expect(afterSuccess.overdueSince == nil)
        #expect(afterSuccess.lastSnapshotAt == fixture.clock.now)
    }

    @Test("A failed run leaves a job overdue")
    func failureLeavesItOverdue() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        fixture.clock.advance(by: 14 * 60 * 60)

        // Act
        let run = try await fixture.run()

        // Assert
        #expect(run.failure == .sourceEmpty)
        #expect(try await fixture.status().overdueSince != nil)
    }
}
