import Foundation

/// Brings a Hive back from one of its recovery files (§14), on a Hive that has no configuration yet.
/// Hive takes it only from Beekeeper on its own Mac, since it carries the recovery key itself.
public struct RestoreRequest: Codable, Sendable {
    /// The whole `.hiverecovery` file.
    public let file: Data
    /// As the person typed it. Hive opens the file with it and forgets it.
    public let recoveryKeyCode: String

    public init(file: Data, recoveryKeyCode: String) {
        self.file = file
        self.recoveryKeyCode = recoveryKeyCode
    }
}

/// What a restore brought back. Hive restarts straight after, as the Hive the file describes.
public struct RestoreOutcome: Codable, Hashable, Sendable {
    /// The restored Hive's ID, which Beekeeper signs in to from then on.
    public let hiveID: UUID
    public let hiveName: String
    /// The restored Hive's port, which it listens on once it has restarted.
    public let port: Int
    public let serverCount: Int
    public let jobCount: Int
    /// Taken over from the backup drive. Nil when the file's drive isn't mounted, so it has to be chosen again.
    public let snapshotCount: Int?

    public init(hiveID: UUID, hiveName: String, port: Int, serverCount: Int, jobCount: Int, snapshotCount: Int?) {
        self.hiveID = hiveID
        self.hiveName = hiveName
        self.port = port
        self.serverCount = serverCount
        self.jobCount = jobCount
        self.snapshotCount = snapshotCount
    }
}

/// Sent with 422 when Hive won't restore, which then changes nothing.
public struct RestoreRefusal: Codable, Hashable, Sendable {
    public let problem: RestoreProblem

    public init(problem: RestoreProblem) {
        self.problem = problem
    }
}

public enum RestoreProblem: String, Codable, Hashable, Sendable {
    /// Only Beekeeper on the Hive's own Mac can restore, so the recovery key never crosses a network.
    case notOnThisMac
    /// The Hive has servers, email, a recovery key or a backup drive already.
    case alreadySetUp
    /// The key's check character doesn't match, so it was mistyped.
    case mistypedKey
    case notARecoveryFile
    /// Written by a newer Hive.
    case unsupportedFile
    /// Written for another recovery key.
    case otherKey
    /// Altered or cut short.
    case couldNotOpen
}

/// Whether the Hive can still be restored, and after a restore, what it took over while retention waits.
public struct RestoreState: Codable, Hashable, Sendable {
    /// The Hive has no configuration yet, so it can be restored from a recovery file.
    public let canRestore: Bool
    /// Set by a restore. Retention and quotas remove nothing until a device starts them again, since a
    /// drive restored from a Mac backup may have lost its hard links (§10).
    public let retentionPausedSince: Date?
    /// While retention waits: each server and job, and what it has on the chosen drive.
    public let servers: [RestoredServer]

    public init(canRestore: Bool, retentionPausedSince: Date?, servers: [RestoredServer]) {
        self.canRestore = canRestore
        self.retentionPausedSince = retentionPausedSince
        self.servers = servers
    }
}

public struct RestoredServer: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let quotaBytes: Int64?
    /// Its jobs' snapshots on the chosen drive. Nil until each job is counted.
    public let usedBytes: Int64?
    public let jobs: [RestoredJob]

    public init(id: UUID, name: String, quotaBytes: Int64?, usedBytes: Int64?, jobs: [RestoredJob]) {
        self.id = id
        self.name = name
        self.quotaBytes = quotaBytes
        self.usedBytes = usedBytes
        self.jobs = jobs
    }
}

public struct RestoredJob: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    /// Complete snapshots on the chosen drive.
    public let snapshotCount: Int

    public init(id: UUID, name: String, snapshotCount: Int) {
        self.id = id
        self.name = name
        self.snapshotCount = snapshotCount
    }
}
