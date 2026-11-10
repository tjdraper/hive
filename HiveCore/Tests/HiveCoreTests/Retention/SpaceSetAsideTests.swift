import Darwin
import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

/// APFS can give a file space past its end, which it takes back only later. Counted, that space would
/// stay in a job's space for good and lead a quota to remove snapshots early (§10).
struct SpaceSetAsideTests {
    private static let blockSize: Int64 = 4096

    /// Gives `url` `extra` bytes past its end, as APFS does for a file rsync writes over the network.
    private static func setAside(_ extra: Int64, after url: URL) throws {
        let descriptor = open(url.fileSystemPath, O_RDWR)
        try #require(descriptor >= 0)
        defer { close(descriptor) }
        var store = fstore_t(
            fst_flags: UInt32(F_ALLOCATEALL),
            fst_posmode: F_PEOFPOSMODE,
            fst_offset: 0,
            fst_length: off_t(extra),
            fst_bytesalloc: 0
        )
        try #require(fcntl(descriptor, F_PREALLOCATE, &store) == 0)
    }

    private static func allocated(_ url: URL) throws -> Int64 {
        var info = stat()
        try #require(lstat(url.fileSystemPath, &info) == 0)
        return Int64(info.st_blocks) * 512
    }

    private static func wholeBlocks(_ bytes: Int64) -> Int64 {
        (bytes + blockSize - 1) / blockSize * blockSize
    }

    @Test("A file with space set aside past its end counts only its size in whole blocks")
    func setAsideNotCounted() throws {
        // Arrange
        let temporary = try TemporaryDirectory()
        let tree = temporary.url.appending(path: "Tree", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        let file = tree.appending(path: "upload.bin")
        try Data(repeating: 7, count: 100_000).write(to: file)
        try Self.setAside(10_000_000, after: file)
        try #require(try Self.allocated(file) > Self.wholeBlocks(100_000))

        // Act
        let tally = try DriveFolder(name: "Tree", in: DriveFolder(at: temporary.url)).tally()

        // Assert
        #expect(try tally.exclusiveBytes == Self.wholeBlocks(100_000) + Self.allocated(tree))
    }

    @Test("A sparse file counts the space it has, which is less than its size")
    func sparseCountsAllocated() throws {
        // Arrange
        let temporary = try TemporaryDirectory()
        let tree = temporary.url.appending(path: "Tree", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        let file = tree.appending(path: "disk.img")
        FileManager.default.createFile(atPath: file.fileSystemPath, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seek(toOffset: 50_000_000)
        try handle.write(contentsOf: Data([1]))
        try handle.close()
        let allocated = try Self.allocated(file)
        try #require(allocated < 50_000_000)

        // Act
        let tally = try DriveFolder(name: "Tree", in: DriveFolder(at: temporary.url)).tally()

        // Assert
        #expect(try tally.exclusiveBytes == allocated + Self.allocated(tree))
    }

    @Test("Space set aside past a file's end doesn't lead a quota to remove a snapshot, and over the quota the oldest daily still goes")
    func quotaIgnoresSetAside() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        let snapshots = try await fixture.runDaysApart([1, 1, 1])
        let used = try #require(try fixture.usedBytes())
        let newest = fixture.snapshotURL(snapshots[2]).appending(path: "files/site")
        let own = try #require(try FileManager.default.contentsOfDirectory(atPath: newest.fileSystemPath).first { $0.hasPrefix("run-") })
        try Self.setAside(10_000_000, after: newest.appending(path: own))
        // Counted again whole, as after an update, while the space is still set aside.
        try await fixture.database.writer.write { database in
            try database.execute(sql: "DELETE FROM jobSpace")
            try database.execute(sql: "UPDATE snapshot SET isCounted = 0, freesBytes = NULL")
        }

        // Act
        try await fixture.setQuota(used)
        await fixture.retentionPass()
        let keptAtQuota = try fixture.completeSnapshots().map(\.id)
        try await fixture.setQuota(used - 1)
        await fixture.retentionPass()

        // Assert
        #expect(keptAtQuota == snapshots.map(\.id))
        #expect(try fixture.completeSnapshots().map(\.id) == snapshots[1...].map(\.id))
        #expect(try await fixture.removals().flatMap(\.removed).map(\.snapshotID) == [snapshots[0].id])
    }
}
