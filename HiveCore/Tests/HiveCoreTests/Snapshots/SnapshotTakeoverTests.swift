import CryptoKit
import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

struct SnapshotTakeoverTests {
    /// What the catalog knows about a snapshot that a manifest can give back.
    struct Cataloged: Equatable {
        let id: UUID
        let jobID: UUID
        let serverID: UUID
        let driveUUID: String
        let folders: [String]
        let state: SnapshotState
        let startedAt: Date
        let completedAt: Date?

        init(_ record: SnapshotRecord) {
            id = record.id
            jobID = record.jobID
            serverID = record.serverID
            driveUUID = record.driveUUID
            folders = record.parts
            state = record.state
            startedAt = record.startedAt
            completedAt = record.completedAt
        }
    }

    @Test("The catalog rebuilt from manifests matches the one it replaces, and skips snapshots from another Hive")
    func rebuildMatches() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try await fixture.runDaysApart([1, 1, 1])
        let before = try fixture.catalog().map(Cataloged.init)
        let jobFolder = try fixture.jobFolder()
        try Self.writeForeignSnapshot(in: jobFolder, named: "2027-01-01T000000Z")
        try FileManager.default.createDirectory(
            at: jobFolder.appending(path: "2027-01-02T000000Z"), withIntermediateDirectories: false
        )
        try FileManager.default.createSymbolicLink(
            at: jobFolder.appending(path: "2027-01-03T000000Z"),
            withDestinationURL: fixture.snapshotURL(try #require(try fixture.catalog().first))
        )
        try fixture.forgetCatalog()

        // Act
        let outcome = try fixture.takeOver()

        // Assert
        #expect(outcome.takenOver == 3)
        #expect(outcome.skipped == 2)
        #expect(try fixture.catalog().map(Cataloged.init) == before)
        #expect(try fixture.catalog().allSatisfy { !$0.isCounted && $0.freesBytes == nil })
        #expect(try fixture.usedBytes() == nil)
        #expect(try RetentionStore(database: fixture.database).isPaused())
    }

    @Test("Taking over again finds nothing new, and leaves retention as it was")
    func takingOverAgain() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try await fixture.runDaysApart([1, 1])

        // Act
        let outcome = try fixture.takeOver()

        // Assert
        #expect(outcome == SnapshotCatalogBuilder.Outcome(takenOver: 0, known: 2, skipped: 0))
        #expect(try !RetentionStore(database: fixture.database).isPaused())
        #expect(try fixture.usedBytes() != nil)
    }

    @Test("A drive restored from a Mac backup, with a new volume UUID and no hard links, is taken over when chosen")
    func restoredDriveChosen() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try await fixture.runDaysApart([1, 1])
        let before = try fixture.catalog().map(Cataloged.init)
        let restored = fixture.temporary.url.appending(path: "Restored", directoryHint: .isDirectory)
        // Copied file by file, as a restore from a Mac backup can be, so nothing is linked any more.
        try FileManager.default.copyItem(at: fixture.volume, to: restored)
        let restoredUUID = UUID()
        fixture.api.volumes.set([BackupRunFixture.volume(at: restored, uuid: restoredUUID)])

        // Act
        let answer = try await fixture.api.send(.put, HiveEndpoint.backupDrive, json: BackupDriveChoice(volumeUUID: restoredUUID))
        await fixture.runs.waitUntilIdle()

        // Assert
        #expect(answer.status == .ok)
        let after = try fixture.catalog()
        #expect(after.map(\.id) == before.map(\.id))
        #expect(after.allSatisfy { $0.driveUUID == restoredUUID.uuidString })
        #expect(after.map(\.parts) == before.map(\.folders))
        #expect(try RetentionStore(database: fixture.database).isPaused())
        // Counted again on the restored drive, where its files now take more space than before.
        let used = try SnapshotSpaceStore(database: fixture.database).usedBytes(ofJob: fixture.job.id, onDrive: restoredUUID.uuidString)
        #expect(used != nil)
    }

    @Test("Retention and quotas remove nothing after snapshots are taken over, until a device starts them again")
    func retentionWaits() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        let snapshots = try await fixture.runDaysApart([1, 1, 1, 1])
        try fixture.forgetCatalog()
        try fixture.takeOver()
        try await fixture.setTiers(daily: 1, monthly: 1)
        try await fixture.setQuota(1)

        // Act
        await fixture.retentionPass()
        let whilePaused = try fixture.completeSnapshots()
        let removedWhilePaused = try await fixture.removals()
        let started = try await fixture.api.sendConfirmed(.delete, HiveEndpoint.retentionPause)
        await fixture.runs.waitUntilIdle()

        // Assert
        #expect(whilePaused.map(\.id) == snapshots.map(\.id))
        #expect(removedWhilePaused.isEmpty)
        #expect(try fixture.usedBytes() != nil)
        #expect(started.status == .noContent)
        let newest = try #require(snapshots.last)
        #expect(try fixture.completeSnapshots().map(\.id) == [newest.id])
        #expect(try !RetentionStore(database: fixture.database).isPaused())
        #expect(try fixture.api.auditEvents().first == .retentionStarted)
    }

    @Test("While retention waits it still counts each job, whole")
    func countsWhilePaused() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try await fixture.runDaysApart([1, 1])
        try fixture.forgetCatalog()
        try fixture.takeOver()

        // Act
        await fixture.retentionPass()

        // Assert
        #expect(try fixture.usedBytes() == DriveUsage.bytes(under: fixture.jobFolder()))
        let state = try await fixture.api.send(.get, HiveEndpoint.restore).decoded(as: RestoreState.self)
        let server = try #require(state.servers.only)
        #expect(server.usedBytes == (try fixture.usedBytes()))
        #expect(server.jobs.map(\.snapshotCount) == [2])
    }

    @Test("Starting retention when it isn't waiting changes nothing")
    func startingWhenNotPaused() async throws {
        // Arrange
        let fixture = try APIFixture()
        let before = try fixture.auditEvents()

        // Act
        let answer = try await fixture.sendConfirmed(.delete, HiveEndpoint.retentionPause)

        // Assert
        #expect(answer.status == .notFound)
        #expect(try fixture.auditEvents() == before)
    }

    @Test("A restored Hive takes over the drive's snapshots, counts them without removing any, and backs up again")
    func restoreThenBackUp() async throws {
        // Arrange
        let old = try await BackupRunFixture()
        try await old.runDaysApart([1, 1])
        let key = RecoveryKey()
        try await old.api.saveRecoveryKey(key)
        let before = try old.catalog().map(Cataloged.init)
        let new = try APIFixture()
        new.volumes.set([BackupRunFixture.volume(at: old.volume)])

        // Act
        let outcome = try new.restore(Data(contentsOf: old.api.recoveryFile), key: key)
        let restarted = try APIFixture(signIn: SignInFixture(restarting: new.signIn), sealer: new.sealer)
        restarted.volumes.set([BackupRunFixture.volume(at: old.volume)])
        await restarted.api.runs.requestRetentionPass()
        await restarted.api.runs.waitUntilIdle()
        restarted.signIn.clock.advance(by: 3 * 24 * 60 * 60)
        let run = try await restarted.send(.post, HiveEndpoint.run(ofJob: old.job.id))
        await restarted.api.runs.waitUntilIdle()

        // Assert
        #expect(outcome.snapshotCount == 2)
        let catalog = try restarted.catalog()
        #expect(Array(catalog.prefix(2).map(Cataloged.init)) == before)
        #expect(run.status == .accepted)
        #expect(catalog.count == 3)
        #expect(catalog.allSatisfy { $0.state == .complete })
        #expect(try RetentionStore(database: restarted.signIn.database).isPaused())
    }

    /// A snapshot whose manifest is another Hive's.
    private static func writeForeignSnapshot(in jobFolder: URL, named name: String) throws {
        let folder = jobFolder.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let manifest = SnapshotManifest(
            format: SnapshotManifest.currentFormat,
            hiveID: UUID(),
            snapshotID: UUID(),
            server: SnapshotManifest.Named(id: UUID(), name: "Other"),
            job: SnapshotManifest.Named(id: UUID(), name: "Other"),
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            completedAt: Date(timeIntervalSince1970: 1_800_000_000),
            complete: true,
            directories: [],
            databases: []
        )
        try manifest.encoded().write(to: folder.appending(path: SnapshotManifest.fileName))
    }
}

extension APIFixture {
    func catalog() throws -> [SnapshotRecord] {
        try signIn.database.writer.read { try SnapshotRecord.order(Column("startedAt")).fetchAll($0) }
    }
}

extension BackupRunFixture {
    /// As if Hive's store had been lost: the catalog and every job's space are gone.
    func forgetCatalog() throws {
        try database.writer.write { database in
            try database.execute(sql: "DELETE FROM snapshot")
            try database.execute(sql: "DELETE FROM jobSpace")
        }
    }

    @discardableResult
    func takeOver() throws -> SnapshotCatalogBuilder.Outcome {
        let drive = LocatedDrive(
            identity: BackupDriveIdentity(volumeUUID: Self.volumeUUID, name: "Test Drive"),
            hiveFolder: hiveFolder
        )
        return try SnapshotCatalogBuilder(database: database, hiveID: api.signIn.hiveID, now: { [clock] in clock.now }).takeOver(drive)
    }
}
