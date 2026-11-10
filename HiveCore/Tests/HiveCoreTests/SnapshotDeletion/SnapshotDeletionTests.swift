import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

/// Deleting snapshots by hand removes exactly the ones asked for, between runs (§10).
struct SnapshotDeletionTests {
    /// Three snapshots a day apart.
    private static func threeSnapshots() async throws -> (BackupRunFixture, [SnapshotRecord]) {
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        return (fixture, try await fixture.runDaysApart([1, 1, 1]))
    }

    private static func delete(_ path: String, in fixture: BackupRunFixture) async throws -> APIAnswer {
        let answer = try await fixture.api.sendConfirmed(.delete, path)
        await fixture.runs.waitUntilIdle()
        return answer
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.fileSystemPath)
    }

    @Test("Deleting a snapshot removes it and nothing else, logged in the job log and the audit log")
    func deletesOne() async throws {
        // Arrange
        let (fixture, snapshots) = try await Self.threeSnapshots()
        let kept = [snapshots[0], snapshots[2]]
        let keptContents = kept.map { BackupRunFixture.contents(of: fixture.snapshotURL($0)) }

        // Act
        let answer = try await Self.delete(HiveEndpoint.snapshot(snapshots[1].id), in: fixture)

        // Assert
        #expect(answer.status == .accepted)
        #expect(try fixture.completeSnapshots().map(\.id) == kept.map(\.id))
        #expect(!Self.exists(fixture.snapshotURL(snapshots[1])))
        #expect(kept.map { BackupRunFixture.contents(of: fixture.snapshotURL($0)) } == keptContents)
        let removed = try await fixture.removals().flatMap(\.removed)
        #expect(removed.map(\.snapshotID) == [snapshots[1].id])
        #expect(removed.first?.reason == .deletedByDevice)
        #expect(try fixture.api.auditEvents().first == .snapshotsDeleted(.snapshot(
            jobID: fixture.job.id,
            serverName: fixture.serverRecord.name,
            jobName: fixture.job.name,
            date: snapshots[1].date
        )))
    }

    @Test("Deleting a job's snapshots leaves another job's alone")
    func deletesJob() async throws {
        // Arrange
        let (fixture, _) = try await Self.threeSnapshots()
        let other = try await fixture.addJob(named: "Other")
        let otherSnapshots = try await fixture.runDaysApart([1], job: other, source: "srv/Other")

        // Act
        let answer = try await Self.delete(HiveEndpoint.snapshots(ofJob: fixture.job.id), in: fixture)

        // Assert
        #expect(answer.status == .accepted)
        #expect(try fixture.completeSnapshots().isEmpty)
        #expect(try fixture.completeSnapshots(of: other).map(\.id) == otherSnapshots.map(\.id))
        #expect(otherSnapshots.allSatisfy { Self.exists(fixture.snapshotURL($0)) })
        #expect(try fixture.api.auditEvents().first == .snapshotsDeleted(.job(
            jobID: fixture.job.id,
            serverName: fixture.serverRecord.name,
            jobName: fixture.job.name,
            count: 3
        )))
    }

    @Test("A removed job's snapshots are listed, read and deleted, and its job log entry keeps its names")
    func deletesRemovedJob() async throws {
        // Arrange
        let (fixture, snapshots) = try await Self.threeSnapshots()
        _ = try await fixture.api.send(.delete, HiveEndpoint.job(fixture.job.id))

        // Act
        let listed = try await fixture.api.send(.get, HiveEndpoint.removedJobs).decoded(as: [RemovedJob].self)
        let read = try await fixture.api.send(.get, HiveEndpoint.snapshots(ofJob: fixture.job.id)).decoded(as: JobSnapshots.self)
        let answer = try await Self.delete(HiveEndpoint.snapshots(ofJob: fixture.job.id), in: fixture)

        // Assert
        #expect(listed.map(\.jobID) == [fixture.job.id])
        #expect(listed.first?.jobName == fixture.job.name)
        #expect(listed.first?.serverName == fixture.serverRecord.name)
        #expect(listed.first?.isServerRemoved == false)
        #expect(listed.first?.snapshotCount == 3)
        #expect(Set(read.snapshots.map(\.id)) == Set(snapshots.map(\.id)))
        #expect(answer.status == .accepted)
        #expect(try fixture.catalog().isEmpty)
        let removal = try #require(try await fixture.removals().first)
        #expect(removal.jobName == fixture.job.name)
        #expect(Set(removal.removed.map(\.snapshotID)) == Set(snapshots.map(\.id)))
        #expect(try await fixture.api.send(.get, HiveEndpoint.removedJobs).decoded(as: [RemovedJob].self).isEmpty)
        #expect(try await fixture.api.send(.get, HiveEndpoint.snapshots(ofJob: fixture.job.id)).status == .notFound)
    }

    @Test("Deleting a removed server's snapshots deletes its removed jobs' too")
    func deletesRemovedServer() async throws {
        // Arrange
        let (fixture, snapshots) = try await Self.threeSnapshots()
        _ = try await fixture.api.send(.delete, HiveEndpoint.server(fixture.serverRecord.id))
        let listed = try await fixture.api.send(.get, HiveEndpoint.removedJobs).decoded(as: [RemovedJob].self)

        // Act
        let answer = try await Self.delete(HiveEndpoint.snapshots(ofServer: fixture.serverRecord.id), in: fixture)

        // Assert
        #expect(listed.first?.isServerRemoved == true)
        #expect(answer.status == .accepted)
        #expect(try fixture.catalog().isEmpty)
        #expect(snapshots.allSatisfy { !Self.exists(fixture.snapshotURL($0)) })
        #expect(try fixture.api.auditEvents().first == .snapshotsDeleted(.server(
            serverID: fixture.serverRecord.id,
            serverName: fixture.serverRecord.name,
            count: 3
        )))
    }

    @Test("A deletion asked for while the drive is missing shows as under way, and happens once it's back")
    func waitsForDrive() async throws {
        // Arrange
        let (fixture, snapshots) = try await Self.threeSnapshots()
        fixture.ejectDrive()

        // Act
        let answer = try await Self.delete(HiveEndpoint.snapshot(snapshots[0].id), in: fixture)
        let whileMissing = try await fixture.api.send(.get, HiveEndpoint.snapshots(ofJob: fixture.job.id)).decoded(as: JobSnapshots.self)
        fixture.mountDrive()
        await fixture.retentionPass()

        // Assert
        #expect(answer.status == .accepted)
        #expect(whileMissing.snapshots.first { $0.id == snapshots[0].id }?.state == .removing)
        #expect(whileMissing.snapshots.filter { $0.state == .removing }.count == 1)
        #expect(try fixture.completeSnapshots().map(\.id) == snapshots[1...].map(\.id))
        #expect(!Self.exists(fixture.snapshotURL(snapshots[0])))
    }

    @Test("The partial snapshot a run is writing can't be deleted, and an older one waits for the run to finish")
    func waitsForRun() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        let older = try await fixture.runDaysApart([1])
        // A snapshot completing in the same second as the last would need the same folder name.
        fixture.clock.advance(by: 60)
        fixture.databaseServer.hold()
        _ = try await fixture.runNow()
        try await fixture.waitUntilRunning(BackupRunFixture.dumping)
        let partial = try #require(try fixture.catalog().first { $0.state == .partial })

        // Act
        let refused = try await fixture.api.sendConfirmed(.delete, HiveEndpoint.snapshot(partial.id))
        let accepted = try await fixture.api.sendConfirmed(.delete, HiveEndpoint.snapshot(older[0].id))
        let duringRun = try fixture.catalog().map(\.id)
        fixture.databaseServer.release()
        await fixture.runs.waitUntilIdle()

        // Assert
        #expect(refused.status == .conflict)
        #expect(accepted.status == .accepted)
        #expect(duringRun.contains(older[0].id))
        let left = try fixture.completeSnapshots()
        #expect(left.map(\.id) == [partial.id])
        #expect(Self.exists(fixture.snapshotURL(left[0])))
    }

    @Test("Asking to delete what isn't there is answered 404, and records nothing")
    func nothingToDelete() async throws {
        // Arrange
        let (fixture, _) = try await Self.threeSnapshots()
        let before = try fixture.api.auditEvents()

        // Act
        let snapshot = try await fixture.api.sendConfirmed(.delete, HiveEndpoint.snapshot(UUID()))
        let job = try await fixture.api.sendConfirmed(.delete, HiveEndpoint.snapshots(ofJob: UUID()))
        let server = try await fixture.api.sendConfirmed(.delete, HiveEndpoint.snapshots(ofServer: UUID()))

        // Assert
        #expect([snapshot.status, job.status, server.status] == [.notFound, .notFound, .notFound])
        #expect(try fixture.api.auditEvents() == before)
    }
}
