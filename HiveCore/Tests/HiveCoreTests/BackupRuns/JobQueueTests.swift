import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct JobQueueTests {
    /// Which job started or finished, in order, until `count` of them have.
    private func startsAndFinishes(in events: AsyncStream<RunEvent>, count: Int) async -> [String] {
        var seen: [String] = []
        for await event in events {
            switch event {
            case .started(let entry): seen.append("started \(entry.jobName)")
            case .finished(let entry): seen.append("finished \(entry.jobName)")
            default: continue
            }
            if seen.count == count { break }
        }
        return seen
    }

    @Test("Run Now while another job runs waits its turn, and runs never overlap")
    func oneAtATime() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        let other = try await fixture.addJob(named: "Other")
        let events = fixture.runs.events.listen()
        fixture.databaseServer.hold()
        _ = try await fixture.runNow()
        try await fixture.waitUntilRunning(BackupRunFixture.dumping)

        // Act
        let queued = try await fixture.runNow(other)
        let waiting = try queued.decoded(as: JobStatus.self)
        fixture.databaseServer.release()
        await fixture.runs.waitUntilIdle()

        // Assert
        #expect(queued.status == .accepted)
        #expect(waiting.state == .waiting)
        #expect(await startsAndFinishes(in: events, count: 4) == [
            "started \(fixture.job.name)", "finished \(fixture.job.name)", "started Other", "finished Other",
        ])
        #expect(try await fixture.status(of: other).lastRun?.run.failure == nil)
    }

    @Test("Run Now goes ahead of scheduled runs already waiting")
    func runNowFirst() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        let scheduled = try await fixture.addJob(named: "Scheduled")
        let pressed = try await fixture.addJob(named: "Pressed")
        let events = fixture.runs.events.listen()
        fixture.databaseServer.hold()
        _ = try await fixture.runNow()
        try await fixture.waitUntilRunning(BackupRunFixture.dumping)

        // Act
        _ = try await fixture.runs.queueScheduled(jobID: scheduled.id)
        _ = try await fixture.runNow(pressed)
        fixture.databaseServer.release()
        await fixture.runs.waitUntilIdle()

        // Assert
        let order = await startsAndFinishes(in: events, count: 6).filter { $0.hasPrefix("started") }
        #expect(order == ["started \(fixture.job.name)", "started Pressed", "started Scheduled"])
    }

    @Test("A job waiting or running can't be queued again")
    func notQueuedTwice() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        let other = try await fixture.addJob(named: "Other")
        fixture.databaseServer.hold()
        _ = try await fixture.runNow()
        try await fixture.waitUntilRunning(BackupRunFixture.dumping)
        _ = try await fixture.runNow(other)

        // Act
        let running = try await fixture.runNow()
        let waiting = try await fixture.runNow(other)
        let scheduled = try await fixture.runs.queueScheduled(jobID: other.id)
        fixture.databaseServer.release()
        await fixture.runs.waitUntilIdle()

        // Assert
        #expect(running.status == .conflict)
        #expect(waiting.status == .conflict)
        #expect(scheduled == .alreadyQueued)
        #expect(try await fixture.jobLog().entries.count == 2)
    }

    @Test("Cancelling a waiting run takes it out of the queue without an entry in the job log, and is audited")
    func cancelWaiting() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        let other = try await fixture.addJob(named: "Other")
        fixture.databaseServer.hold()
        _ = try await fixture.runNow()
        try await fixture.waitUntilRunning(BackupRunFixture.dumping)
        _ = try await fixture.runNow(other)

        // Act
        let cancelled = try await fixture.api.send(.delete, HiveEndpoint.run(ofJob: other.id))
        let status = try await fixture.status(of: other)
        fixture.databaseServer.release()
        await fixture.runs.waitUntilIdle()

        // Assert
        #expect(cancelled.status == .noContent)
        #expect(status.state == .idle)
        #expect(try await fixture.jobLog("?job=\(other.id)").entries.isEmpty)
        #expect(try fixture.api.auditEvents().first == .backupRunCancelled(
            jobID: other.id, serverName: fixture.serverRecord.name, jobName: "Other"
        ))
    }

    @Test("Cancelling a running run stops its dump and ends it cancelled, and the next run picks up its partial snapshot")
    func cancelRunning() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        fixture.databaseServer.hold()
        _ = try await fixture.runNow()
        try await fixture.waitUntilRunning(BackupRunFixture.dumping)

        // Act
        let cancelled = try await fixture.api.send(.delete, HiveEndpoint.run(ofJob: fixture.job.id))
        await fixture.runs.waitUntilIdle()
        let stopped = try #require(try await fixture.status().lastRun)
        let partials = try fixture.catalog().filter { $0.state == .partial }.count
        fixture.databaseServer.release()
        let next = try await fixture.run()

        // Assert
        #expect(cancelled.status == .noContent)
        #expect(stopped.run.failure == .cancelled)
        #expect(stopped.run.directories.count == 1)
        #expect(partials == 1)
        #expect(next.failure == nil)
        #expect(next.pickedUpPartialSnapshot)
        #expect(try fixture.snapshots().count == 1)
        #expect(try fixture.api.auditEvents().contains(.backupRunCancelled(
            jobID: fixture.job.id, serverName: fixture.serverRecord.name, jobName: fixture.job.name
        )))
    }

    @Test("Cancelling a job with nothing waiting or running, or no job at all, is not found and isn't audited")
    func cancelNothing() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        let before = try fixture.api.auditEvents()

        // Act
        let idle = try await fixture.api.send(.delete, HiveEndpoint.run(ofJob: fixture.job.id))
        let unknown = try await fixture.api.send(.delete, HiveEndpoint.run(ofJob: UUID()))

        // Assert
        #expect(idle.status == .notFound)
        #expect(unknown.status == .notFound)
        #expect(try fixture.api.auditEvents() == before)
    }

    @Test("A run can't be cancelled without signing in")
    func cancelRefusedWithoutSigningIn() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        fixture.databaseServer.hold()
        _ = try await fixture.runNow()
        try await fixture.waitUntilRunning(BackupRunFixture.dumping)
        let before = try fixture.api.auditEvents()
        let path = HiveEndpoint.run(ofJob: fixture.job.id)

        // Act
        try await fixture.api.application.test(.router) { client in
            try await client.execute(uri: path, method: .delete) { response in
                // Assert
                #expect(response.status == .unauthorized)
            }
        }
        fixture.databaseServer.release()
        await fixture.runs.waitUntilIdle()

        // Assert
        #expect(try await fixture.status().lastRun?.run.failure == nil)
        #expect(try fixture.api.auditEvents() == before)
    }

    @Test("The Mac is kept awake while a run goes, and allowed to sleep once it ends")
    func keepsTheMacAwake() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        fixture.databaseServer.hold()

        // Act
        _ = try await fixture.runNow()
        try await fixture.waitUntilRunning(BackupRunFixture.dumping)
        let heldWhileRunning = fixture.api.sleepPrevention.held
        fixture.databaseServer.release()
        await fixture.runs.waitUntilIdle()

        // Assert
        #expect(heldWhileRunning == 1)
        #expect(fixture.api.sleepPrevention.held == 0)
        #expect(fixture.api.sleepPrevention.taken == 1)
    }

    @Test("A running job's status shows what it's doing and how far it has got")
    func runningStatus() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        fixture.databaseServer.hold()

        // Act
        _ = try await fixture.runNow()
        try await fixture.waitUntilRunning(BackupRunFixture.dumping)
        let status = try await fixture.status()
        let all = try await fixture.api.send(.get, HiveEndpoint.jobStatus).decoded(as: [JobStatus].self)
        fixture.databaseServer.release()
        await fixture.runs.waitUntilIdle()

        // Assert
        #expect(status.state == .running)
        #expect(status.step == BackupRunFixture.dumping)
        #expect(status.current?.trigger == .runNow)
        #expect(status.current?.run.directories.map(\.folder) == ["site"])
        #expect(status.overdueSince == nil)
        #expect(all == [status])
    }
}
