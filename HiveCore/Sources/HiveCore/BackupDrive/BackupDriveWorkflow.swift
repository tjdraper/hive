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

    /// Claims the volume's `Hive` folder for this Hive, then records the choice.
    func choose(_ choice: BackupDriveChoice, by deviceID: UUID) throws -> BackupDriveState {
        guard let volume = volumes.mountedVolumes().first(where: { $0.uuid == choice.volumeUUID }) else {
            throw refusal(.notMounted)
        }
        if let problem = volume.unsuitability ?? HiveDriveFolder.claim(on: volume.url, hiveID: hiveID) {
            throw refusal(problem)
        }
        try store.choose(BackupDriveIdentity(volumeUUID: volume.uuid, name: volume.name), by: deviceID, at: now())
        Self.logger.notice("Chose the backup drive")
        return try state()
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
