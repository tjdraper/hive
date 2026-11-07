import Darwin
import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

/// Counts trees in temporary folders, and snapshots the bundled rsync made, against a count the long way.
struct SpaceCountingTests {
    /// Three snapshots in a job folder, as `--link-dest` leaves them: a file all three share, one the
    /// first two share, and one of each's own.
    private static func linkedSnapshots(in temporary: TemporaryDirectory) throws -> URL {
        let job = temporary.url.appending(path: "Job", directoryHint: .isDirectory)
        let names = ["2026-06-01T120000Z", "2026-06-02T120000Z", "2026-06-03T120000Z"]
        for name in names {
            try FileManager.default.createDirectory(at: job.appending(path: "\(name)/files/site"), withIntermediateDirectories: true)
        }
        let first = job.appending(path: "\(names[0])/files/site")
        try Data(repeating: 1, count: 300_000).write(to: first.appending(path: "shared-by-all.jpg"))
        try Data(repeating: 2, count: 100_000).write(to: first.appending(path: "first-two.txt"))
        for (index, name) in names.enumerated() {
            let site = job.appending(path: "\(name)/files/site")
            try Data(repeating: UInt8(10 + index), count: 50_000 * (index + 1)).write(to: site.appending(path: "own.txt"))
            if index > 0 {
                let shared = "shared-by-all.jpg"
                try FileManager.default.linkItem(at: first.appending(path: shared), to: site.appending(path: shared))
            }
        }
        try FileManager.default.linkItem(
            at: first.appending(path: "first-two.txt"),
            to: job.appending(path: "\(names[1])/files/site/first-two.txt")
        )
        return job
    }

    @Test("What a tree frees, counted by inode, matches what removing it frees")
    func tallyMatchesRemoval() throws {
        // Arrange
        let temporary = try TemporaryDirectory()
        let job = try Self.linkedSnapshots(in: temporary)
        let folder = try DriveFolder(at: job)
        let names = try FileManager.default.contentsOfDirectory(atPath: job.fileSystemPath).sorted()

        for name in names {
            let before = DriveUsage.blocks(under: job)
            let expectedFreed = try DriveFolder(name: name, in: folder).tally().exclusiveBytes

            // Act
            try folder.removeFolder(name)

            // Assert
            #expect(DriveUsage.freed(from: before, to: DriveUsage.blocks(under: job)) == expectedFreed)
        }
    }

    @Test("A tree with files linked inside it counts each file once")
    func linksInsideCountOnce() throws {
        // Arrange
        let temporary = try TemporaryDirectory()
        let tree = temporary.url.appending(path: "Tree", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tree.appending(path: "a"), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 200_000).write(to: tree.appending(path: "a/one.bin"))
        try FileManager.default.linkItem(at: tree.appending(path: "a/one.bin"), to: tree.appending(path: "two.bin"))

        // Act
        let tally = try DriveFolder(name: "Tree", in: DriveFolder(at: temporary.url)).tally()

        // Assert
        #expect(tally.exclusiveBytes == DriveUsage.bytes(under: tree))
        #expect(tally.linked.count == 1)
    }

    @Test("A job's space counts each file once across its snapshots, and stays exact through runs and removals")
    func jobSpaceStaysExact() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write(String(repeating: "shared ", count: 30_000), to: "srv/site/big.txt")
        try await fixture.setTiers(daily: 3, monthly: 0)

        // Act
        let snapshots = try await fixture.runDaysApart([1, 1, 1, 1, 1])

        // Assert
        #expect(snapshots.count == 3)
        #expect(try fixture.usedBytes() == fixture.snapshotBlocks().values.reduce(0, +))
        let removals = try await fixture.removals()
        #expect(removals.flatMap(\.removed).count == 2)
        #expect(try fixture.catalog().allSatisfy { $0.isCounted && $0.freesBytes != nil })
    }

    @Test("What each snapshot is said to free matches what removing it frees")
    func freesMatchesRemoval() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write(String(repeating: "shared ", count: 30_000), to: "srv/site/big.txt")
        let snapshots = try await fixture.runDaysApart([1, 1, 1])
        let middle = try #require(try fixture.catalog().first { $0.id == snapshots[1].id })
        let said = try #require(middle.freesBytes)
        let before = try fixture.snapshotBlocks()
        let usedBefore = try #require(try fixture.usedBytes())

        // Act
        try await fixture.setTiers(daily: 1, monthly: 0)
        await fixture.retentionPass()

        // Assert
        let removed = try await fixture.removals().flatMap(\.removed)
        #expect(removed.map(\.snapshotID) == [snapshots[0].id, snapshots[1].id])
        #expect(removed.last?.bytesFreed ?? 0 >= said)
        let freed = DriveUsage.freed(from: before, to: try fixture.snapshotBlocks())
        #expect(removed.reduce(0) { $0 + $1.bytesFreed } == freed)
        #expect(try fixture.usedBytes() == usedBefore - freed)
        #expect(try fixture.usedBytes() == fixture.snapshotBlocks().values.reduce(0, +))
    }

    @Test("A picked-up partial is counted again when its run ends, and the job's space stays exact")
    func pickedUpPartialCounted() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write(String(repeating: "shared ", count: 30_000), to: "srv/site/big.txt")
        try await fixture.runDaysApart([1])
        try fixture.write("can't be read", to: "srv/site/locked.txt")
        chmod(fixture.source("srv/site/locked.txt").fileSystemPath, 0)
        try await fixture.runDaysApart([1])
        let partial = try #require(try fixture.catalog().first { $0.state == .partial })
        #expect(partial.isCounted)
        #expect(try fixture.usedBytes() == fixture.snapshotBlocks().values.reduce(0, +))
        chmod(fixture.source("srv/site/locked.txt").fileSystemPath, 0o644)

        // Act
        try await fixture.runDaysApart([1])

        // Assert
        #expect(try fixture.catalog().first { $0.id == partial.id }?.state == .complete)
        #expect(try fixture.usedBytes() == fixture.snapshotBlocks().values.reduce(0, +))
    }

    @Test("A job counted for the first time, such as after an update, is counted whole")
    func firstCountIsWhole() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write(String(repeating: "shared ", count: 30_000), to: "srv/site/big.txt")
        try await fixture.runDaysApart([1, 1, 1])
        try await fixture.database.writer.write { database in
            try database.execute(sql: "DELETE FROM jobSpace")
            try database.execute(sql: "UPDATE snapshot SET isCounted = 0, freesBytes = NULL")
        }

        // Act
        await fixture.retentionPass()

        // Assert
        #expect(try fixture.usedBytes() == fixture.snapshotBlocks().values.reduce(0, +))
        #expect(try fixture.catalog().allSatisfy { $0.isCounted && $0.freesBytes != nil })
    }
}
