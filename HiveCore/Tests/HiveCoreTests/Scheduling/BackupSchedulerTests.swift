import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

/// The fixture's clock starts at 03:00 on 15 January 2027 in New York, and its job runs at 02:30 and 14:00.
struct BackupSchedulerTests {
    private func date(_ text: String) throws -> Date {
        try Date(text, strategy: .iso8601)
    }

    private func check(_ fixture: BackupRunFixture) async {
        await fixture.api.api.scheduler.check()
        await fixture.runs.waitUntilIdle()
    }

    @Test("A new job waits for its first time rather than running at once")
    func newJobWaits() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")

        // Act
        await check(fixture)

        // Assert
        let status = try await fixture.status()
        #expect(status.lastRun == nil)
        #expect(status.nextRunAt == (try date("2027-01-15T14:00:00-05:00")))
    }

    @Test("A job is queued when its time comes and runs, then waits for its next time")
    func runsAtItsTime() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        await check(fixture)
        fixture.clock.advance(by: 11 * 60 * 60 - 1)
        await check(fixture)
        let before = try await fixture.jobLog().runs

        // Act
        fixture.clock.advance(by: 30)
        await check(fixture)

        // Assert
        #expect(before.isEmpty)
        let entries = try await fixture.jobLog().runs
        #expect(entries.count == 1)
        #expect(entries.first?.trigger == .scheduled)
        #expect(entries.first?.run.failure == nil)
        #expect(try fixture.snapshots().count == 1)
        #expect(try await fixture.status().nextRunAt == (try date("2027-01-16T02:30:00-05:00")))
    }

    @Test("Times missed while Hive was off or the Mac asleep run the job once, not once for each")
    func missedTimesRunOnce() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        await check(fixture)

        // Act
        fixture.clock.advance(by: 3 * 24 * 60 * 60)
        await check(fixture)
        await check(fixture)

        // Assert
        let entries = try await fixture.jobLog().runs
        #expect(entries.count == 1)
        #expect(entries.first?.trigger == .scheduled)
        #expect(try await fixture.status().nextRunAt == (try date("2027-01-18T14:00:00-05:00")))
    }

    @Test("A job's time coming while it's already running doesn't queue it again")
    func notQueuedWhileRunning() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        await check(fixture)
        fixture.databaseServer.hold()
        _ = try await fixture.runNow()
        try await fixture.waitUntilRunning(BackupRunFixture.dumping)

        // Act
        fixture.clock.advance(by: 11 * 60 * 60)
        await fixture.api.api.scheduler.check()
        fixture.databaseServer.release()
        await fixture.runs.waitUntilIdle()

        // Assert
        let entries = try await fixture.jobLog().runs
        #expect(entries.map(\.trigger) == [.runNow])
        #expect(try await fixture.status().nextRunAt == (try date("2027-01-16T02:30:00-05:00")))
    }

    @Test("Changing a job's times works out its next run again, without running it for a time already past")
    func changedTimes() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        await check(fixture)
        var draft = fixture.job.draft
        draft.times = [TimeOfDay(hour: 1, minute: 0)]

        // Act
        let answer = try await fixture.api.send(.put, HiveEndpoint.job(fixture.job.id), json: draft)
        await check(fixture)

        // Assert
        #expect(answer.status == .ok)
        #expect(try await fixture.jobLog().runs.isEmpty)
        #expect(try await fixture.status().nextRunAt == (try date("2027-01-16T01:00:00-05:00")))
    }

    @Test("Job log entries are kept for a year, and an unfinished one is never removed")
    func jobLogKeptForAYear() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        let now = fixture.clock.now
        let day: TimeInterval = 24 * 60 * 60
        let (jobID, serverID) = (fixture.job.id, fixture.serverRecord.id)
        try await fixture.api.signIn.database.writer.write { database in
            for (age, finished) in [(400 * day, true), (366 * day, true), (364 * day, true), (400 * day, false)] {
                var entry = JobLogRecord(
                    id: nil, jobID: jobID, serverID: serverID, serverName: "Server", jobName: "Job",
                    trigger: .scheduled, startedAt: now - age, finishedAt: finished ? now - age + 60 : nil, failure: nil,
                    pickedUpPartialSnapshot: false, directories: [], databases: []
                )
                try entry.insert(database)
            }
        }

        // Act
        await check(fixture)

        // Assert
        let kept = try await fixture.jobLog().runs.map { now.timeIntervalSince($0.run.startedAt) / day }
        #expect(kept == [400, 364])
    }
}
