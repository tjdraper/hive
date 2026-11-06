import Foundation
import HiveKit
import os

/// Pulls one of a job's directories into its folder in the snapshot, linking unchanged files to the
/// previous snapshot's copies.
struct DirectoryPull: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Backup")

    let rsync: RsyncRunner

    /// `previous` is the same directory's folder in the job's last complete snapshot, when it has one.
    func pull(
        _ directory: BackupDirectory,
        from origin: RsyncOrigin,
        into destination: URL,
        linkingTo previous: URL?
    ) async throws -> DirectoryRun {
        let started = ContinuousClock.now
        let result = try await rsync.pull(directory.path, from: origin, into: destination, linkingTo: previous)
        let seconds = (ContinuousClock.now - started).roundedSeconds
        let outcome = RsyncResultReader.pull(result)
        let statistics = outcome.statistics

        var failure = outcome.failure
        if failure == nil, Self.isEmpty(destination) { failure = .sourceEmpty }

        if let failure {
            let (reason, status) = (failure.rawValue, result.status)
            Self.logger.error("""
            Pulling a directory failed: \(reason, privacy: .public), exit \(status, privacy: .public), after \(seconds, privacy: .public)s
            """)
        } else {
            let (files, bytes, received) = (statistics.filesTransferred, statistics.bytesTransferred, statistics.bytesReceived)
            let notes = (outcome.vanishedFiles ? ", some files vanished" : "") + (previous == nil ? ", nothing to link to" : "")
            Self.logger.notice("""
            Pulled a directory in \(seconds, privacy: .public)s: \(files, privacy: .public) files (\(bytes, privacy: .public) bytes) \
            transferred, \(received, privacy: .public) bytes received\(notes, privacy: .public)
            """)
        }

        return DirectoryRun(
            folder: directory.folder,
            seconds: seconds,
            filesTransferred: statistics.filesTransferred,
            bytesTransferred: statistics.bytesTransferred,
            bytesReceived: statistics.bytesReceived,
            vanishedFiles: outcome.vanishedFiles,
            failure: failure
        )
    }

    private static func isEmpty(_ folder: URL) -> Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.fileSystemPath)) ?? []).isEmpty
    }
}
