import Foundation
import HiveKit
import os

/// Dumps one of a job's databases into the snapshot's `databases/` folder: finds its container when
/// it runs in one, then streams the dump over SSH straight into its file (§9). A dump that fails
/// leaves no file behind.
struct DatabaseDump: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Backup")

    let runner: DatabaseDumpRunner

    /// `password` is nil when none is stored.
    func dump(_ database: BackupDatabase, password: String?, from origin: BackupOrigin, into folder: URL) async throws -> DatabaseRun {
        let settings = database.settings
        let started = ContinuousClock.now
        let file = folder.appending(path: DumpCommand.fileName(for: settings), directoryHint: .notDirectory)

        var summary = DumpFileSummary()
        var failure: BackupFailure?
        do {
            if let password {
                switch try await container(for: settings, from: origin) {
                case .success(let containerID):
                    (summary, failure) = try await stream(settings, password: password, inContainer: containerID, from: origin, into: file)
                case .failure(let lookup):
                    failure = lookup.failure
                }
            } else {
                failure = .databasePasswordMissing
            }
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        if failure != nil { try? FileManager.default.removeItem(at: file) }

        let seconds = (ContinuousClock.now - started).roundedSeconds
        let (kind, location) = (settings.kind.rawValue, settings.location.logName)
        if let failure {
            Self.logger.error("""
            Dumping a \(kind, privacy: .public) database \(location, privacy: .public) failed after \
            \(seconds, privacy: .public)s: \(failure.rawValue, privacy: .public)
            """)
        } else {
            let (dumped, stored) = (summary.bytesDumped, summary.bytesStored)
            Self.logger.notice("""
            Dumped a \(kind, privacy: .public) database \(location, privacy: .public) in \(seconds, privacy: .public)s: \
            \(dumped, privacy: .public) bytes, \(stored, privacy: .public) stored
            """)
        }
        return DatabaseRun(
            name: settings.name,
            seconds: seconds,
            bytesDumped: summary.bytesDumped,
            bytesStored: summary.bytesStored,
            failure: failure
        )
    }

    private struct LookupFailure: Error {
        let failure: BackupFailure
    }

    /// The container's ID, or nil for a database on the host.
    private func container(for settings: DatabaseSettings, from origin: BackupOrigin) async throws -> Result<String?, LookupFailure> {
        guard case .container(let serviceName) = settings.location else { return .success(nil) }
        let result = try await runner.run(DumpCommand.containerList(), from: origin)
        guard result.status == 0 else {
            let failure = DumpResultReader.failure(of: result)
            // A shell that can't find `docker` exits as it would for a missing dump tool.
            return .failure(LookupFailure(failure: failure == .databaseDumpToolMissing ? .dockerUnavailable : failure))
        }
        switch ContainerListReader.match(serviceName: serviceName, in: result.standardOutput) {
        case .found(let id): return .success(id)
        case .notFound: return .failure(LookupFailure(failure: .databaseContainerNotFound))
        case .notUnique: return .failure(LookupFailure(failure: .databaseContainerNotUnique))
        }
    }

    private func stream(
        _ settings: DatabaseSettings,
        password: String,
        inContainer containerID: String?,
        from origin: BackupOrigin,
        into file: URL
    ) async throws -> (DumpFileSummary, BackupFailure?) {
        let writer: DumpFileWriter
        do {
            writer = try DumpFileWriter(creating: file, compressed: settings.kind == .mysql)
        } catch {
            return (DumpFileSummary(), .couldNotWriteSnapshot)
        }

        let result: ChildProcess.Result
        let summary: DumpFileSummary
        do {
            result = try await runner.run(
                DumpCommand.dump(settings, inContainer: containerID),
                input: DumpCommand.input(for: settings, password: password),
                from: origin,
                output: { try writer.write($0) }
            )
            summary = try writer.finish()
        } catch is DumpFileError {
            return (DumpFileSummary(), .couldNotWriteSnapshot)
        }
        return (summary, DumpResultReader.failure(of: result, kind: settings.kind, dump: summary))
    }
}

extension DatabaseLocation {
    /// Where a database runs, without naming its container, for the system log.
    var logName: String {
        switch self {
        case .host: "on the host"
        case .container: "in a container"
        }
    }
}
