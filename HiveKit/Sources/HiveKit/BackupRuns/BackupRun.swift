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

    public init(jobID: UUID, startedAt: Date, finishedAt: Date?, failure: BackupFailure?, directories: [DirectoryRun]) {
        self.jobID = jobID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.failure = failure
        self.directories = directories
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
    /// Hive couldn't write the snapshot to the backup drive.
    case couldNotWriteSnapshot
    case cancelled
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
