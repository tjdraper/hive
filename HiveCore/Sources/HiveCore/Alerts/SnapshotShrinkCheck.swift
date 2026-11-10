import Foundation
import HiveKit

/// Whether a complete snapshot is much smaller than the one before (§9), which can mean files were
/// lost on the server, or a database emptied, without anything failing.
enum SnapshotShrinkCheck {
    /// Shrinking to less than half counts.
    static let shrunkBelow = 0.5
    /// Parts smaller than this come and go without meaning much.
    static let smallestCompared: Int64 = 1_000_000

    /// Each directory and database smaller than `shrunkBelow` of what it was in `previous`. Parts
    /// only one of the runs has aren't compared, since the job was changed in between.
    static func shrunkParts(of run: BackupRun, comparedWith previous: BackupRun) -> [ShrunkPart] {
        let directories = run.directories.compactMap { directory -> ShrunkPart? in
            let before = previous.directories.first { $0.folder == directory.folder }
            guard let bytes = directory.totalBytes, let previousBytes = before?.totalBytes else { return nil }
            return shrunk(.directory, name: directory.folder, from: previousBytes, to: bytes)
        }
        let databases = run.databases.compactMap { database -> ShrunkPart? in
            guard let before = previous.databases.first(where: { $0.name == database.name }) else { return nil }
            return shrunk(.database, name: database.name, from: before.bytesDumped, to: database.bytesDumped)
        }
        return directories + databases
    }

    private static func shrunk(_ kind: ShrunkPart.Kind, name: String, from previousBytes: Int64, to bytes: Int64) -> ShrunkPart? {
        guard previousBytes >= smallestCompared, Double(bytes) < Double(previousBytes) * shrunkBelow else { return nil }
        return ShrunkPart(kind: kind, name: name, previousBytes: previousBytes, bytes: bytes)
    }
}
