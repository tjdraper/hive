import Foundation

/// A change made to the Hive, which device made it and when. Never holds the value of a secret.
public struct AuditEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: Int64
    public let date: Date
    public let deviceID: UUID
    /// The device's name when it made the change, so the entry still reads the same after it's revoked.
    public let deviceName: String
    public let event: AuditEvent

    public init(id: Int64, date: Date, deviceID: UUID, deviceName: String, event: AuditEvent) {
        self.id = id
        self.date = date
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.event = event
    }
}

public enum AuditEvent: Codable, Hashable, Sendable {
    /// The device that made the change is the one that paired, as Beekeeper on the Hive Mac.
    case pairedOnHiveMac
    case deviceRevoked(deviceID: UUID, deviceName: String)
    case hiveRenamed(old: String, new: String)
    case networkAccessChanged(old: NetworkAccess, new: NetworkAccess)
    case portChanged(old: Int, new: Int)
    /// The server's name as it was after the change.
    case server(serverID: UUID, serverName: String, change: ServerChange)
    /// The names as they were after the change.
    case backupJob(jobID: UUID, serverName: String, jobName: String, change: BackupJobChange)
    case backupDriveChosen(old: BackupDriveIdentity?, new: BackupDriveIdentity)
    /// Run Now: a run was queued.
    case backupRunStarted(jobID: UUID, serverName: String, jobName: String)
    /// A waiting run was taken out of the queue, or a running one stopped.
    case backupRunCancelled(jobID: UUID, serverName: String, jobName: String)
    /// Snapshots a device asked to delete, which Hive deletes between runs. The job log records each one removed.
    case snapshotsDeleted(SnapshotDeletion)
    /// The device registered the key it confirms changes with.
    case confirmationKeyRegistered
    /// Hive made a new identity key, and every device was unpaired.
    case identityRegenerated
    case email(EmailChange)
}

public enum EmailChange: Codable, Hashable, Sendable {
    case setUp(EmailSettings)
    /// A changed host also cleared the password, unless a new one was entered with it.
    case changed(old: EmailSettings, new: EmailSettings)
    /// A password was entered. Its value is never recorded.
    case passwordEntered
    /// Email was turned off, and its password cleared.
    case turnedOff
}

/// What a device asked to delete, with the names as they were, or for a removed job as last known.
public enum SnapshotDeletion: Codable, Hashable, Sendable {
    case snapshot(jobID: UUID, serverName: String, jobName: String, date: Date)
    case job(jobID: UUID, serverName: String, jobName: String, count: Int)
    case server(serverID: UUID, serverName: String, count: Int)
}

public enum ServerChange: Codable, Hashable, Sendable {
    case added(connection: ServerConnection)
    case renamed(old: String, new: String)
    /// Also cleared its jobs' database passwords and its confirmed host key.
    case connection(old: ServerConnection, new: ServerConnection)
    case quota(old: Int64?, new: Int64?)
    /// Fingerprints. A device confirmed the key a scan found.
    case hostKeyConfirmed(old: HostKeyFingerprint?, new: HostKeyFingerprint)
    /// Fingerprints of Hive's SSH key for the server. The server needs the new one in `authorized_keys`.
    case newSSHKey(old: String?, new: String)
    /// Its configuration only. Its snapshots stay on the backup drive.
    case removed
}

public enum BackupJobChange: Codable, Hashable, Sendable {
    case added
    case renamed(old: String, new: String)
    case directories(old: [BackupDirectory], new: [BackupDirectory])
    case databases(old: [DatabaseSettings], new: [DatabaseSettings])
    /// A password was entered. Its value is never recorded.
    case databasePassword(databaseName: String)
    case times(old: [TimeOfDay], new: [TimeOfDay])
    case retention(old: RetentionTiers, new: RetentionTiers)
    /// Its configuration only. Its snapshots stay on the backup drive.
    case removed
}

public struct AuditLogPage: Codable, Hashable, Sendable {
    public let entries: [AuditEntry]
    /// Pass as `before` for the next, older page. Nil on the last page.
    public let nextBefore: Int64?

    public init(entries: [AuditEntry], nextBefore: Int64?) {
        self.entries = entries
        self.nextBefore = nextBefore
    }
}
