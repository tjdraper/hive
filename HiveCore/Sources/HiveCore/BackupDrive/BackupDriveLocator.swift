import Foundation
import HiveKit

/// The backup drive, mounted and marked as this Hive's, with its `Hive` folder.
struct LocatedDrive: Sendable {
    let identity: BackupDriveIdentity
    let hiveFolder: URL
}

enum DriveLookup: Sendable {
    case ready(LocatedDrive)
    case unavailable(BackupFailure)
}

/// Finds the chosen drive among the mounted volumes by its UUID, on every run. It never goes by path,
/// since a missing drive's mount point under `/Volumes` is just a folder on the startup disk (§9).
struct BackupDriveLocator: Sendable {
    let store: BackupDriveStore
    let volumes: any VolumeListing
    let hiveID: UUID

    /// Writes nothing.
    func locate() throws -> DriveLookup {
        guard let chosen = try store.chosen() else { return .unavailable(.driveNotChosen) }
        guard let volume = volumes.mountedVolumes().first(where: { $0.uuid == chosen.volumeUUID }) else {
            return .unavailable(.driveMissing)
        }
        switch HiveDriveFolder.mark(on: volume.url, hiveID: hiveID) {
        case .thisHive:
            return .ready(LocatedDrive(identity: chosen, hiveFolder: HiveDriveFolder.url(on: volume.url)))
        case .unreadable:
            return .unavailable(.couldNotWriteSnapshot)
        case .anotherHive, .unclaimed, .inUse:
            return .unavailable(.driveNotThisHives)
        }
    }
}
