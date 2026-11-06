import Foundation

/// The drive Hive writes snapshots to, and the Mac's volumes it could use instead.
public struct BackupDriveState: Codable, Hashable, Sendable {
    /// Nil until one is chosen.
    public let chosen: ChosenBackupDrive?
    public let volumes: [BackupVolume]

    public init(chosen: ChosenBackupDrive?, volumes: [BackupVolume]) {
        self.chosen = chosen
        self.volumes = volumes
    }
}

public struct ChosenBackupDrive: Codable, Hashable, Sendable {
    public let drive: BackupDriveIdentity
    /// Nil when Hive can write snapshots to it now.
    public let problem: BackupDriveProblem?

    public init(drive: BackupDriveIdentity, problem: BackupDriveProblem?) {
        self.drive = drive
        self.problem = problem
    }
}

/// Hive knows its drive by the volume's UUID, never by its path, since a missing drive's mount point
/// is just a folder on the startup disk.
public struct BackupDriveIdentity: Codable, Hashable, Sendable {
    public let volumeUUID: UUID
    /// The volume's name when it was chosen.
    public let name: String

    public init(volumeUUID: UUID, name: String) {
        self.volumeUUID = volumeUUID
        self.name = name
    }
}

/// A volume mounted on the Hive Mac.
public struct BackupVolume: Codable, Hashable, Sendable {
    public let volumeUUID: UUID
    public let name: String
    /// As Finder describes it, such as "APFS (Case-sensitive)".
    public let format: String
    public let totalBytes: Int64
    public let availableBytes: Int64
    /// Nil when Hive can use it.
    public let problem: BackupDriveProblem?

    public init(volumeUUID: UUID, name: String, format: String, totalBytes: Int64, availableBytes: Int64, problem: BackupDriveProblem?) {
        self.volumeUUID = volumeUUID
        self.name = name
        self.format = format
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.problem = problem
    }
}

/// Sent to choose the backup drive.
public struct BackupDriveChoice: Codable, Hashable, Sendable {
    public let volumeUUID: UUID

    public init(volumeUUID: UUID) {
        self.volumeUUID = volumeUUID
    }
}

/// Sent with 422 when Hive won't use a volume, which then changes nothing.
public struct BackupDriveRefusal: Codable, Hashable, Sendable {
    public let problem: BackupDriveProblem

    public init(problem: BackupDriveProblem) {
        self.problem = problem
    }
}

public enum BackupDriveProblem: String, Codable, Hashable, Sendable {
    /// No mounted volume has the drive's UUID.
    case notMounted
    case notAPFS
    /// Linux servers can hold `Foo.jpg` and `foo.jpg` side by side, and a case-insensitive volume keeps only one.
    case notCaseSensitive
    case readOnly
    /// Backups go on a drive of their own, never the Mac's startup disk.
    case startupDisk
    /// Only a drive attached to the Hive Mac, never a network volume.
    case notLocal
    /// Its `Hive` folder is marked as another Hive's, so this Hive never writes there.
    case belongsToAnotherHive
    /// Its `Hive` folder has no mark of this Hive and already holds something.
    case folderInUse
    /// Hive couldn't write its folder there, which can mean it lacks Full Disk Access.
    case notWritable
}
