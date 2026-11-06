import Foundation
import HiveKit
import os

/// Lists the top of each of a job's directories on the server before anything is made on the drive,
/// so a missing or empty one fails the run instead of making a snapshot that looks like a success (§9).
/// A directory emptied in the moments between this and its pull is caught by `DirectoryPull`.
struct SourceCheck: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Backup")

    let rsync: RsyncRunner

    /// Nil when every directory exists and holds something.
    func problem(with directories: [BackupDirectory], from origin: RsyncOrigin) async throws -> BackupFailure? {
        for (index, directory) in directories.enumerated() {
            let started = ContinuousClock.now
            let listing = try await RsyncResultReader.listing(in: rsync.list(directory.path, from: origin))
            let seconds = (ContinuousClock.now - started).roundedSeconds
            let which = "directory \(index + 1) of \(directories.count)"
            switch listing {
            case .hasFiles:
                Self.logger.info("Checked \(which, privacy: .public) in \(seconds, privacy: .public)s")
            case .empty:
                Self.logger.error("The \(which, privacy: .public) is empty")
                return .sourceEmpty
            case .failed(let failure):
                Self.logger.error("Couldn't list \(which, privacy: .public): \(failure.rawValue, privacy: .public)")
                return failure
            }
        }
        return nil
    }
}
