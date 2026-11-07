import Darwin
import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

/// Removal never touches anything outside the snapshot it removes (§10).
struct SnapshotRemovalTests {
    private struct TwoSnapshots {
        let fixture: BackupRunFixture
        let snapshots: [SnapshotRecord]
        /// Outside the drive's `Hive` folder, with `keep.txt` in it.
        let outside: URL
    }

    /// Two snapshots a day apart, and a folder outside the drive's `Hive` folder with a file in it.
    private static func twoSnapshots() async throws -> TwoSnapshots {
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        let snapshots = try await fixture.runDaysApart([1, 1])
        let outside = fixture.temporary.url.appending(path: "Outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("not Hive's".utf8).write(to: outside.appending(path: "keep.txt"))
        return TwoSnapshots(fixture: fixture, snapshots: snapshots, outside: outside)
    }

    private static func remover(_ fixture: BackupRunFixture) -> SnapshotRemover {
        SnapshotRemover(
            removals: SnapshotRemovalStore(database: fixture.database),
            space: SnapshotSpaceStore(database: fixture.database)
        )
    }

    private static func folders(of record: SnapshotRecord) -> SnapshotFolders {
        SnapshotFolders(server: record.serverFolder, job: record.jobFolder)
    }

    private static func jobFolder(_ fixture: BackupRunFixture) throws -> DriveFolder {
        let record = try #require(try fixture.catalog().first)
        let hive = try DriveFolder(at: fixture.hiveFolder)
        return try DriveFolder(name: record.jobFolder, in: DriveFolder(name: record.serverFolder, in: hive))
    }

    @Test("Links inside a snapshot are removed, never followed")
    func linksNotFollowed() async throws {
        // Arrange
        let arranged = try await Self.twoSnapshots()
        let (fixture, snapshots, outside) = (arranged.fixture, arranged.snapshots, arranged.outside)
        let files = fixture.snapshotURL(snapshots[0]).appending(path: "files/site")
        try FileManager.default.createSymbolicLink(at: files.appending(path: "to-folder"), withDestinationURL: outside)
        let keep = outside.appending(path: "keep.txt")
        try FileManager.default.createSymbolicLink(at: files.appending(path: "to-file"), withDestinationURL: keep)
        try await fixture.setTiers(daily: 1, monthly: 0)

        // Act
        await fixture.retentionPass()

        // Assert
        #expect(try fixture.completeSnapshots().map(\.id) == [snapshots[1].id])
        #expect(!FileManager.default.fileExists(atPath: fixture.snapshotURL(snapshots[0]).fileSystemPath))
        #expect(BackupRunFixture.contents(of: outside) == ["keep.txt"])
        #expect(try String(contentsOf: outside.appending(path: "keep.txt"), encoding: .utf8) == "not Hive's")
    }

    @Test("A catalog entry with `..` or a path for a name, another job's folders, or another drive is refused")
    func badCatalogEntries() async throws {
        // Arrange
        let arranged = try await Self.twoSnapshots()
        let (fixture, snapshots) = (arranged.fixture, arranged.snapshots)
        let other = try await fixture.addJob(named: "other")
        let otherSnapshots = try await fixture.runDaysApart([1], job: other, source: "srv/other")
        let real = snapshots[0]
        let jobFolder = try Self.jobFolder(fixture)
        let decoy = try Self.decoy(beside: otherSnapshots[0], in: fixture)
        let entries = [
            Self.entry(like: real, folder: ".."),
            Self.entry(like: real, folder: "\(real.folder)/files"),
            Self.entry(like: real, folder: "../\(otherSnapshots[0].jobFolder)/\(otherSnapshots[0].folder)"),
            Self.entry(like: otherSnapshots[0], jobID: real.jobID, folder: decoy.lastPathComponent),
            Self.entry(like: real, driveUUID: UUID().uuidString),
        ]
        try await fixture.database.writer.write { database in
            for entry in entries { try entry.insert(database) }
        }

        // Act
        let outcomes = try entries.map { entry in
            try Self.remover(fixture).remove(
                entry,
                because: .outsideTiers,
                in: jobFolder,
                folders: Self.folders(of: real),
                driveUUID: BackupRunFixture.volumeUUID.uuidString
            )
        }

        // Assert
        #expect(outcomes == Array(repeating: .refused(.notInJobFolder), count: entries.count))
        #expect(try fixture.snapshots().allSatisfy { FileManager.default.fileExists(atPath: $0.fileSystemPath) })
        #expect(BackupRunFixture.contents(of: decoy) == ["keep.txt"])
    }

    /// A folder with a snapshot's name in another job's folder, which the catalog doesn't know.
    private static func decoy(beside record: SnapshotRecord, in fixture: BackupRunFixture) throws -> URL {
        let jobFolder = fixture.snapshotURL(record).deletingLastPathComponent()
        let decoy = jobFolder.appending(path: "2020-01-01T000000Z", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: decoy, withIntermediateDirectories: true)
        try Data("not this job's".utf8).write(to: decoy.appending(path: "keep.txt"))
        return decoy
    }

    private static func entry(
        like record: SnapshotRecord,
        jobID: UUID? = nil,
        folder: String? = nil,
        driveUUID: String? = nil
    ) -> SnapshotRecord {
        SnapshotRecord(
            id: UUID(),
            jobID: jobID ?? record.jobID,
            serverID: record.serverID,
            driveUUID: driveUUID ?? record.driveUUID,
            serverFolder: record.serverFolder,
            jobFolder: record.jobFolder,
            folder: folder ?? record.folder,
            state: .complete,
            startedAt: record.startedAt.addingTimeInterval(-10 * 24 * 60 * 60),
            completedAt: record.date.addingTimeInterval(-10 * 24 * 60 * 60),
            isCounted: true,
            freesBytes: 0
        )
    }

    @Test("A pass leaves alone a catalog entry pointing at another job's snapshot, however old")
    func passLeavesMisplacedEntries() async throws {
        // Arrange
        let arranged = try await Self.twoSnapshots()
        let (fixture, snapshots) = (arranged.fixture, arranged.snapshots)
        let other = try await fixture.addJob(named: "other")
        let target = try #require(try await fixture.runDaysApart([1], job: other, source: "srv/other").first)
        let decoy = try Self.decoy(beside: target, in: fixture)
        let misplaced = Self.entry(like: target, jobID: snapshots[0].jobID, folder: decoy.lastPathComponent)
        try await fixture.database.writer.write { try misplaced.insert($0) }
        try await fixture.setTiers(daily: 1, monthly: 0)

        // Act
        await fixture.retentionPass()

        // Assert
        #expect(BackupRunFixture.contents(of: decoy) == ["keep.txt"])
        #expect(FileManager.default.fileExists(atPath: fixture.snapshotURL(target).fileSystemPath))
        #expect(try fixture.catalog().contains { $0.id == misplaced.id })
        #expect(try fixture.completeSnapshots().map(\.id).contains(snapshots[1].id))
    }

    @Test("A snapshot folder or a job folder replaced by a link is never followed")
    func replacedByLinks() async throws {
        // Arrange
        let arranged = try await Self.twoSnapshots()
        let (fixture, snapshots, outside) = (arranged.fixture, arranged.snapshots, arranged.outside)
        let oldest = fixture.snapshotURL(snapshots[0])
        try FileManager.default.removeItem(at: oldest)
        try FileManager.default.createSymbolicLink(at: oldest, withDestinationURL: outside)

        // Act
        let outcome = try Self.remover(fixture).remove(
            snapshots[0],
            because: .outsideTiers,
            in: Self.jobFolder(fixture),
            folders: Self.folders(of: snapshots[0]),
            driveUUID: BackupRunFixture.volumeUUID.uuidString
        )
        let jobFolder = try fixture.jobFolder()
        let moved = fixture.temporary.url.appending(path: "Moved", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: jobFolder, to: moved)
        try FileManager.default.createSymbolicLink(at: jobFolder, withDestinationURL: moved)
        try await fixture.setTiers(daily: 1, monthly: 0)
        await fixture.retentionPass()

        // Assert
        #expect(outcome == .refused(.notInJobFolder))
        #expect(BackupRunFixture.contents(of: outside) == ["keep.txt"])
        #expect(FileManager.default.fileExists(atPath: moved.appending(path: snapshots[1].folder).fileSystemPath))
        #expect(try fixture.catalog().count == 2)
    }

    @Test("A snapshot being written is never removed, and its job is left until the run ends")
    func beingWritten() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        let snapshots = try await fixture.runDaysApart([1, 1])
        try await fixture.setTiers(daily: 1, monthly: 0)
        fixture.databaseServer.hold()
        fixture.clock.advance(by: 24 * 60 * 60)
        _ = try await fixture.runNow()
        try await fixture.waitUntilRunning(BackupRunFixture.dumping)
        let writing = try #require(try fixture.catalog().first { $0.state == .partial })

        // Act
        await fixture.retentionWorkflow().pass()
        let refused = try Self.remover(fixture).remove(
            writing,
            because: .replacedPartial,
            in: Self.jobFolder(fixture),
            folders: Self.folders(of: writing),
            driveUUID: BackupRunFixture.volumeUUID.uuidString
        )
        let duringRun = try fixture.catalog()
        fixture.databaseServer.release()
        await fixture.runs.waitUntilIdle()

        // Assert
        #expect(refused == .refused(.beingWritten))
        #expect(Set(duringRun.map(\.id)) == Set(snapshots.map(\.id) + [writing.id]))
        #expect(try fixture.completeSnapshots().map(\.id) == [writing.id])
    }

    @Test("A snapshot with read-only folders and files is removed completely")
    func readOnlyFolders() async throws {
        // Arrange
        let arranged = try await Self.twoSnapshots()
        let (fixture, snapshots) = (arranged.fixture, arranged.snapshots)
        let site = fixture.snapshotURL(snapshots[0]).appending(path: "files/site")
        try FileManager.default.createDirectory(at: site.appending(path: "locked/deeper/deepest"), withIntermediateDirectories: true)
        try Data("read only".utf8).write(to: site.appending(path: "locked/deeper/deepest/file.txt"))
        chmod(site.appending(path: "locked/deeper/deepest/file.txt").fileSystemPath, 0o444)
        chmod(site.appending(path: "locked/deeper/deepest").fileSystemPath, 0o555)
        chmod(site.appending(path: "locked/deeper").fileSystemPath, 0o000)
        chmod(site.appending(path: "locked").fileSystemPath, 0o500)
        chmod(site.fileSystemPath, 0o555)
        try await fixture.setTiers(daily: 1, monthly: 0)

        // Act
        await fixture.retentionPass()

        // Assert
        var info = stat()
        #expect(lstat(fixture.snapshotURL(snapshots[0]).fileSystemPath, &info) != 0)
        #expect(try fixture.completeSnapshots().map(\.id) == [snapshots[1].id])
        #expect(try await fixture.removals().flatMap(\.notRemoved).isEmpty)
    }

    @Test("A removal cut short is finished by the pass Hive asks for when it starts, and its space taken off once")
    func interruptedRemoval() async throws {
        // Arrange
        let arranged = try await Self.twoSnapshots()
        let (fixture, snapshots) = (arranged.fixture, arranged.snapshots)
        try fixture.write(String(repeating: "big ", count: 50_000), to: "srv/site/big.txt")
        let third = try #require(try await fixture.runDaysApart([1]).last)
        let used = try #require(try fixture.usedBytes())
        let before = try fixture.snapshotBlocks()
        let record = snapshots[0]
        let freed = try DriveFolder(name: record.folder, in: Self.jobFolder(fixture)).tally().exclusiveBytes
        _ = try SnapshotRemovalStore(database: fixture.database).begin(record.id, freesBytes: freed, reason: .outsideTiers)
        let jobFolder = try fixture.jobFolder()
        let removing = jobFolder.appending(path: SnapshotFolderName.removing(record.folder), directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: jobFolder.appending(path: record.folder), to: removing)
        try FileManager.default.removeItem(at: removing.appending(path: "files/site/index.html"))

        // Act
        await fixture.api.api.scheduler.check()
        await fixture.runs.waitUntilIdle()

        // Assert
        #expect(!FileManager.default.fileExists(atPath: removing.fileSystemPath))
        #expect(try Set(fixture.catalog().map(\.id)) == [snapshots[1].id, third.id])
        #expect(try fixture.usedBytes() == used - DriveUsage.freed(from: before, to: fixture.snapshotBlocks()))
        let removed = try await fixture.removals().flatMap(\.removed)
        #expect(removed.map(\.snapshotID) == [record.id])
        #expect(removed.first?.bytesFreed == freed)
    }

    @Test("After a restore, retention counts but removes nothing until it's started again")
    func pausedAfterRestore() async throws {
        // Arrange
        let arranged = try await Self.twoSnapshots()
        let (fixture, snapshots) = (arranged.fixture, arranged.snapshots)
        try await fixture.database.writer.write { try $0.execute(sql: "UPDATE hive SET retentionPausedSince = ?", arguments: [Date()]) }
        try await fixture.database.writer.write { try $0.execute(sql: "DELETE FROM jobSpace") }
        try await fixture.setTiers(daily: 1, monthly: 0)
        try await fixture.setQuota(1)

        // Act
        await fixture.retentionPass()

        // Assert
        #expect(try fixture.completeSnapshots().map(\.id) == snapshots.map(\.id))
        #expect(try fixture.usedBytes() == fixture.snapshotBlocks().values.reduce(0, +))
        #expect(try fixture.overQuota().isEmpty)
        #expect(try await fixture.removals().isEmpty)
    }
}
