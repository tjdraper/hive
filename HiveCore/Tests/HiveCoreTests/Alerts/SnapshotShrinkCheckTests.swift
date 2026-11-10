import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct SnapshotShrinkCheckTests {
    private static func run(directories: [(String, Int64?)], databases: [(String, Int64)] = []) -> BackupRun {
        BackupRun(
            jobID: UUID(),
            startedAt: Date(),
            finishedAt: Date(),
            failure: nil,
            directories: directories.map { folder, total in
                DirectoryRun(
                    folder: folder,
                    seconds: 1,
                    filesTransferred: 0,
                    bytesTransferred: 0,
                    bytesReceived: 0,
                    totalBytes: total,
                    vanishedFiles: false,
                    failure: nil
                )
            },
            databases: databases.map { DatabaseRun(name: $0.0, seconds: 1, bytesDumped: $0.1, bytesStored: $0.1 / 4, failure: nil) },
            pickedUpPartialSnapshot: false
        )
    }

    @Test("Directories and databases under half their size before are found, and those at half or more aren't")
    func halfOrLess() {
        // Arrange
        let previous = Self.run(
            directories: [("uploads", 10_000_000), ("images", 10_000_000)],
            databases: [("site", 8_000_000), ("shop", 8_000_000)]
        )
        let run = Self.run(directories: [("uploads", 4_999_999), ("images", 5_000_000)], databases: [("site", 100), ("shop", 9_000_000)])

        // Act
        let shrunk = SnapshotShrinkCheck.shrunkParts(of: run, comparedWith: previous)

        // Assert
        #expect(shrunk == [
            ShrunkPart(kind: .directory, name: "uploads", previousBytes: 10_000_000, bytes: 4_999_999),
            ShrunkPart(kind: .database, name: "site", previousBytes: 8_000_000, bytes: 100),
        ])
    }

    @Test("Small parts, parts only one run has, and runs from before sizes were counted aren't compared")
    func notCompared() {
        // Arrange
        let previous = Self.run(directories: [("tiny", 900_000), ("old", nil), ("gone", 10_000_000)])
        let run = Self.run(directories: [("tiny", 0), ("old", 0), ("new", 0)])

        // Act
        let shrunk = SnapshotShrinkCheck.shrunkParts(of: run, comparedWith: previous)

        // Assert
        #expect(shrunk.isEmpty)
    }
}
