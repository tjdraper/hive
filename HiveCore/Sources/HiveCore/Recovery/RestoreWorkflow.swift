import CryptoKit
import Foundation
import GRDB
import HiveKit
import os

enum RestoreError: Error, Equatable {
    case refused(RestoreProblem)
}

/// Brings a Hive back on this Mac from one of its recovery files (§14), on a Hive with no configuration
/// yet. Every secret is sealed again for this Mac's storage key, the Hive keeps its ID and recovery key,
/// and the backup drive's snapshots are taken over through their manifests when it's mounted. Hive then
/// restarts as the restored Hive. The recovery key's private half is used only to open the file.
///
/// Its devices stay: Beekeeper on this Mac, which asked, goes on signing in. Devices paired with the
/// old Mac pinned its identity key, which this Mac doesn't have, so each has to pair again.
struct RestoreWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Recovery")

    let database: HiveDatabase
    let settings: HiveSettingsStore
    let sealer: SecretSealer
    let volumes: any VolumeListing
    let restart: HiveRestart
    let now: @Sendable () -> Date

    /// `isFromThisMac` is whether the request came over the loopback interface. Throws
    /// `RestoreError.refused`, changing nothing, when Hive won't restore.
    func restore(_ request: RestoreRequest, isFromThisMac: Bool, by deviceID: UUID) throws -> RestoreOutcome {
        guard isFromThisMac else { throw refusal(.notOnThisMac) }
        let key: RecoveryKey
        do {
            key = try RecoveryKey(code: request.recoveryKeyCode)
        } catch {
            throw refusal(.mistypedKey)
        }
        let contents = try open(request.file, with: key)
        let sealed = try contents.mappingSecrets { try sealer.seal($0).data }

        let date = now()
        try database.writer.write { database in
            guard try RecoveryContentsWriter.isUnconfigured(in: database) else { throw refusal(.alreadySetUp) }
            try RecoveryContentsWriter.write(sealed, recoveryKey: key.publicKey, at: date, in: database)
            let jobCount = contents.servers.flatMap(\.jobs).count
            let event = AuditEvent.restoredFromRecoveryFile(
                writtenAt: contents.writtenAt,
                serverCount: contents.servers.count,
                jobCount: jobCount
            )
            try AuditLog.record(event, by: deviceID, at: date, in: database)
        }
        let port = try settings.settings().port
        let snapshotCount = takeOverSnapshots(hiveID: contents.hive.id)
        // Everything Hive started with carries the old ID, so it starts again as the restored Hive.
        restart.request()
        let jobCount = contents.servers.flatMap(\.jobs).count
        Self.logger.notice("""
        Restored the Hive from a recovery file (\(contents.servers.count, privacy: .public) servers, \
        \(jobCount, privacy: .public) jobs, snapshots taken over: \(snapshotCount.map(String.init) ?? "no drive", privacy: .public))
        """)
        return RestoreOutcome(
            hiveID: contents.hive.id,
            hiveName: contents.hive.name,
            port: port,
            serverCount: contents.servers.count,
            jobCount: jobCount,
            snapshotCount: snapshotCount
        )
    }

    private func open(_ file: Data, with key: RecoveryKey) throws -> RecoveryContents {
        do {
            return try RecoveryFile.open(file, with: key.privateKey)
        } catch let error as RecoveryFileError {
            switch error {
            case .notARecoveryFile: throw refusal(.notARecoveryFile)
            case .unsupportedVersion, .unsupportedContents: throw refusal(.unsupportedFile)
            case .otherKey: throw refusal(.otherKey)
            case .couldNotOpen: throw refusal(.couldNotOpen)
            }
        } catch {
            // The ciphertext opened but its contents didn't decode, which only a changed file could cause.
            throw refusal(.couldNotOpen)
        }
    }

    /// Nil when the restored Hive's drive isn't mounted, such as one restored from a Mac backup with a
    /// new volume UUID, which is chosen again later and taken over then.
    private func takeOverSnapshots(hiveID: UUID) -> Int? {
        let drives = BackupDriveLocator(store: BackupDriveStore(database: database), volumes: volumes, hiveID: hiveID)
        do {
            guard case .ready(let drive) = try drives.locate() else { return nil }
            return try SnapshotCatalogBuilder(database: database, hiveID: hiveID, now: now).takeOver(drive).takenOver
        } catch {
            Self.logger.error("Couldn't take over the backup drive's snapshots: \(String(describing: type(of: error)), privacy: .public)")
            return nil
        }
    }

    private func refusal(_ problem: RestoreProblem) -> RestoreError {
        Self.logger.notice("Refused to restore: \(problem.rawValue, privacy: .public)")
        return .refused(problem)
    }
}
