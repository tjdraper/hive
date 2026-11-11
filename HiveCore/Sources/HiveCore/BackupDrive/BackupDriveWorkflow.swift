import Foundation
import HiveKit
import os

enum BackupDriveChoiceError: Error, Equatable {
    case refused(BackupDriveProblem)
}

/// Showing the Mac's volumes and choosing the one Hive keeps its snapshots on.
struct BackupDriveWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "BackupDrive")

    let store: BackupDriveStore
    let volumes: any VolumeListing
    let hiveID: UUID
    let now: @Sendable () -> Date

    func state() throws -> BackupDriveState {
        let mounted = volumes.mountedVolumes()
        let chosen = try store.chosen().map { drive in
            let volume = mounted.first { $0.uuid == drive.volumeUUID }
            return ChosenBackupDrive(drive: drive, problem: volume.map(problem(with:)) ?? .notMounted)
        }
        let listed = mounted
            .map { volume in
                BackupVolume(
                    volumeUUID: volume.uuid,
                    name: volume.name,
                    format: volume.formatDescription,
                    totalBytes: volume.totalBytes,
                    availableBytes: volume.availableBytes,
                    problem: problem(with: volume)
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return BackupDriveState(chosen: chosen, volumes: listed)
    }

    /// Claims the volume's `Hive` folder for this Hive, records the choice, then takes over any of this
    /// Hive's snapshots the catalog doesn't have, such as on a drive restored from a Mac backup.
    func choose(_ choice: BackupDriveChoice, by deviceID: UUID) throws -> (state: BackupDriveState, tookOverSnapshots: Bool) {
        guard let volume = volumes.mountedVolumes().first(where: { $0.uuid == choice.volumeUUID }) else {
            throw refusal(.notMounted)
        }
        if let problem = volume.unsuitability ?? HiveDriveFolder.claim(on: volume.url, hiveID: hiveID) {
            throw refusal(problem)
        }
        let identity = BackupDriveIdentity(volumeUUID: volume.uuid, name: volume.name)
        try store.choose(identity, by: deviceID, at: now())
        Self.logger.notice("Chose the backup drive")
        let drive = LocatedDrive(identity: identity, hiveFolder: HiveDriveFolder.url(on: volume.url))
        var tookOver = false
        do {
            tookOver = try SnapshotCatalogBuilder(database: store.database, hiveID: hiveID, now: now).takeOver(drive).takenOver > 0
        } catch {
            // The drive is chosen either way. Choosing it again tries again.
            Self.logger.error("Couldn't take over the drive's snapshots: \(String(describing: type(of: error)), privacy: .public)")
        }
        return (try state(), tookOver)
    }

    private func problem(with volume: MountedVolume) -> BackupDriveProblem? {
        if let unsuitability = volume.unsuitability { return unsuitability }
        return switch HiveDriveFolder.mark(on: volume.url, hiveID: hiveID) {
        case .thisHive, .unclaimed: nil
        case .anotherHive: .belongsToAnotherHive
        case .inUse: .folderInUse
        case .unreadable: .notWritable
        }
    }

    private func refusal(_ problem: BackupDriveProblem) -> BackupDriveChoiceError {
        Self.logger.notice("Refused a backup drive: \(problem.rawValue, privacy: .public)")
        return .refused(problem)
    }
}
