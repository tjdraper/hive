import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

/// Hive restarting is started again with `BackupRunCoordinator.start()`, over a store left as a run cut
/// short would leave it.
struct InterruptedRunTests {
    /// Leaves the store as if Hive stopped while the job ran: its entry unfinished, and still marked running.
    private func leaveRunning(_ fixture: BackupRunFixture, trigger: RunTrigger) async throws -> Int64 {
        let (jobID, serverID, now) = (fixture.job.id, fixture.serverRecord.id, fixture.clock.now)
        return try await fixture.api.signIn.database.writer.write { database in
            var entry = JobLogRecord(
                id: nil, jobID: jobID, serverID: serverID, serverName: "Server", jobName: "Job", trigger: trigger,
                startedAt: now, finishedAt: nil, failure: nil, pickedUpPartialSnapshot: false, directories: [], databases: []
            )
            try entry.insert(database)
            try QueuedRunRecord(jobID: jobID, trigger: trigger, queuedAt: now, logEntryID: entry.id).insert(database)
            return try #require(entry.id)
        }
    }

    /// A run cancelled after its directory, leaving a partial snapshot.
    private func leavePartial(_ fixture: BackupRunFixture) async throws {
        fixture.databaseServer.hold()
        _ = try await fixture.runNow()
        try await fixture.waitUntilRunning(BackupRunFixture.dumping)
        _ = try await fixture.api.send(.delete, HiveEndpoint.run(ofJob: fixture.job.id))
        await fixture.runs.waitUntilIdle()
        fixture.databaseServer.release()
    }

    @Test("A run going when Hive stopped is marked interrupted at the next start, and runs again picking up its partial snapshot")
    func interruptedRunsAgain() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        try await leavePartial(fixture)
        let interrupted = try await leaveRunning(fixture, trigger: .scheduled)
        fixture.clock.advance(by: 60)

        // Act
        try await fixture.runs.start()
        await fixture.runs.waitUntilIdle()

        // Assert
        let entries = try await fixture.jobLog().runs
        let marked = try #require(entries.first { $0.id == interrupted })
        #expect(marked.run.failure == .interrupted)
        #expect(marked.run.finishedAt == fixture.clock.now)
        let again = try #require(entries.first)
        #expect(again.trigger == .afterInterruption)
        #expect(again.run.failure == nil)
        #expect(again.run.pickedUpPartialSnapshot)
        #expect(try fixture.snapshots().count == 1)
        #expect(try fixture.catalog().allSatisfy { $0.state == .complete })
    }

    @Test("A run queued after an interruption isn't queued again if it's interrupted too")
    func interruptedOnlyOnce() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        let interrupted = try await leaveRunning(fixture, trigger: .afterInterruption)

        // Act
        try await fixture.runs.start()
        await fixture.runs.waitUntilIdle()

        // Assert
        let entries = try await fixture.jobLog().runs
        #expect(entries.map(\.id) == [interrupted])
        #expect(entries.first?.run.failure == .interrupted)
        #expect(try await fixture.status().state == .idle)
    }

    @Test("Runs waiting when Hive stopped still run after it starts")
    func waitingRunsSurvive() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        let (jobID, now) = (fixture.job.id, fixture.clock.now)
        try await fixture.api.signIn.database.writer.write { database in
            try QueuedRunRecord(jobID: jobID, trigger: .scheduled, queuedAt: now, logEntryID: nil).insert(database)
        }

        // Act
        try await fixture.runs.start()
        await fixture.runs.waitUntilIdle()

        // Assert
        let entries = try await fixture.jobLog().runs
        #expect(entries.map(\.trigger) == [.scheduled])
        #expect(entries.first?.run.failure == nil)
    }

    @Test("A run's progress is saved as it goes, so one cut short still shows what it did")
    func progressSaved() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        fixture.databaseServer.hold()
        _ = try await fixture.runNow()

        // Act
        try await fixture.waitUntilRunning(BackupRunFixture.dumping)
        let saved = try await fixture.api.signIn.database.writer.read { try JobLogRecord.fetchOne($0) }
        fixture.databaseServer.release()
        await fixture.runs.waitUntilIdle()

        // Assert
        #expect(saved?.finishedAt == nil)
        #expect(saved?.directories.map(\.folder) == ["site"])
    }
}
