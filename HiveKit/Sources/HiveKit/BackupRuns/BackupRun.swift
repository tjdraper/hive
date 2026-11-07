import Foundation

/// One run of a backup job: what it copied, how long each part took, and why it failed.
public struct BackupRun: Codable, Hashable, Sendable {
    public let jobID: UUID
    public let startedAt: Date
    /// Nil while it runs.
    public let finishedAt: Date?
    /// Nil while it runs, and once it succeeds.
    public let failure: BackupFailure?
    /// The directories it pulled, in the job's order. One that failed is the last.
    public let directories: [DirectoryRun]
    /// The databases it dumped after the directories, in the job's order. One that failed is the last.
    public let databases: [DatabaseRun]
    /// It carried on with the partial snapshot a failed or interrupted run left, so files that run
    /// already copied weren't copied again.
    public let pickedUpPartialSnapshot: Bool

    public init(
        jobID: UUID,
        startedAt: Date,
        finishedAt: Date?,
        failure: BackupFailure?,
        directories: [DirectoryRun],
        databases: [DatabaseRun],
        pickedUpPartialSnapshot: Bool
    ) {
        self.jobID = jobID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.failure = failure
        self.directories = directories
        self.databases = databases
        self.pickedUpPartialSnapshot = pickedUpPartialSnapshot
    }
}

public struct DirectoryRun: Codable, Hashable, Sendable {
    /// Where it goes within the snapshot.
    public let folder: String
    public let seconds: Double
    /// Files that were new or changed. Unchanged files are linked to the previous snapshot instead.
    public let filesTransferred: Int
    /// The size of those files.
    public let bytesTransferred: Int64
    /// What came over the network, which rsync's delta transfer can keep well below `bytesTransferred`.
    public let bytesReceived: Int64
    /// Files that disappeared on the server while they were being copied. A warning, not a failure.
    public let vanishedFiles: Bool
    public let failure: BackupFailure?

    public init(
        folder: String,
        seconds: Double,
        filesTransferred: Int,
        bytesTransferred: Int64,
        bytesReceived: Int64,
        vanishedFiles: Bool,
        failure: BackupFailure?
    ) {
        self.folder = folder
        self.seconds = seconds
        self.filesTransferred = filesTransferred
        self.bytesTransferred = bytesTransferred
        self.bytesReceived = bytesReceived
        self.vanishedFiles = vanishedFiles
        self.failure = failure
    }
}

public struct DatabaseRun: Codable, Hashable, Sendable {
    /// The database's name, which is unique within its job.
    public let name: String
    public let seconds: Double
    /// The dump as the database wrote it.
    public let bytesDumped: Int64
    /// Its file in the snapshot, which for MySQL and MariaDB is compressed.
    public let bytesStored: Int64
    public let failure: BackupFailure?

    public init(name: String, seconds: Double, bytesDumped: Int64, bytesStored: Int64, failure: BackupFailure?) {
        self.name = name
        self.seconds = seconds
        self.bytesDumped = bytesDumped
        self.bytesStored = bytesStored
        self.failure = failure
    }
}

public enum BackupFailure: String, Codable, Hashable, Sendable {
    /// No backup drive has been chosen.
    case driveNotChosen
    /// The backup drive isn't mounted. Nothing was written.
    case driveMissing
    /// The mounted drive's `Hive` folder isn't marked as this Hive's. Nothing was written.
    case driveNotThisHives
    /// The server has no SSH key of Hive's yet.
    case noSSHKey
    /// Hive connects only once a device has confirmed the server's host key.
    case noConfirmedHostKey
    /// The server answered with a host key other than the confirmed one. Hive refused to go on.
    case hostKeyChanged
    /// The server turned down Hive's key.
    case loginRefused
    /// The host couldn't be found or didn't answer.
    case unreachable
    /// The connection or transfer stopped answering part way.
    case stalled
    /// A directory doesn't exist on the server, or isn't a directory.
    case sourceMissing
    /// A directory on the server is empty, which would make a snapshot that only looks like a success.
    case sourceEmpty
    /// Hive can't read a directory on the server.
    case sourceUnreadable
    /// rsync couldn't copy some files or their attributes.
    case someFilesNotTransferred
    /// No password is stored for a database.
    case databasePasswordMissing
    /// Hive couldn't list the server's Docker containers.
    case dockerUnavailable
    /// No running container has a database's service name.
    case databaseContainerNotFound
    /// More than one running container has a database's service name, so Hive can't tell which to dump.
    case databaseContainerNotUnique
    /// Where a database runs has no `mariadb-dump` or `mysqldump`, or no `pg_dump`.
    case databaseDumpToolMissing
    /// The dump couldn't reach the database server.
    case databaseUnreachable
    /// The database server turned down the user and password.
    case databaseLoginRefused
    /// No database has the name.
    case databaseMissing
    /// The user lacks a privilege the dump needs, such as to read a routine another user owns.
    case databaseNotPermitted
    /// The dump finished without writing anything.
    case databaseDumpEmpty
    /// The dump ended without what a complete one ends with.
    case databaseDumpIncomplete
    /// The dump failed for another reason.
    case databaseDumpFailed
    /// Hive couldn't write the snapshot to the backup drive.
    case couldNotWriteSnapshot
    case cancelled
    /// Hive stopped or restarted while it ran. Its partial snapshot is picked up by the next run.
    case interrupted
    /// Anything else.
    case failed

    public init(_ connection: ConnectionFailure) {
        self = switch connection {
        case .noSSHKey: .noSSHKey
        case .noConfirmedHostKey: .noConfirmedHostKey
        case .hostKeyChanged: .hostKeyChanged
        case .loginRefused: .loginRefused
        case .unreachable: .unreachable
        case .stalled: .stalled
        case .failed: .failed
        }
    }
}
