import Foundation

/// Giving every server a new SSH key of Hive's (§14), such as after a restore when the old Mac may have
/// been stolen. Hive adds the new key to each server's `authorized_keys` with the old one, checks the new
/// one works, then removes the old key's line. It runs between backups, so it may wait for one to finish.
public struct SSHKeyRotationState: Codable, Hashable, Sendable {
    /// Nil until a rotation is started after Hive starts. Hive keeps only the latest.
    public let startedAt: Date?
    /// Nil while it runs.
    public let finishedAt: Date?
    /// Each server's, as it finishes.
    public let results: [SSHKeyRotationResult]

    public init(startedAt: Date?, finishedAt: Date?, results: [SSHKeyRotationResult]) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.results = results
    }

    public var isRunning: Bool {
        startedAt != nil && finishedAt == nil
    }
}

public struct SSHKeyRotationResult: Codable, Hashable, Sendable, Identifiable {
    public let serverID: UUID
    public let serverName: String
    public let outcome: SSHKeyRotationOutcome

    public init(serverID: UUID, serverName: String, outcome: SSHKeyRotationOutcome) {
        self.serverID = serverID
        self.serverName = serverName
        self.outcome = outcome
    }

    public var id: UUID {
        serverID
    }
}

public enum SSHKeyRotationOutcome: Codable, Hashable, Sendable {
    /// The server has only the new key, which Hive uses from now on.
    case rotated(fingerprint: String)
    /// Hive uses the new key, but couldn't remove the old one's line, which the server still accepts.
    case oldKeyLeft(fingerprint: String)
    /// The server keeps its old key, which Hive goes on using.
    case failed(SSHKeyRotationFailure)
    /// The server isn't set up for Hive to connect yet, so there's nothing to rotate.
    case notSetUp
}

public enum SSHKeyRotationFailure: Codable, Hashable, Sendable {
    /// Hive couldn't connect with its old key.
    case connection(ConnectionFailure)
    /// Hive's old key isn't in the server's `~/.ssh/authorized_keys`, such as when the server reads keys from elsewhere.
    case oldKeyNotFound
    case couldNotAddNewKey
    /// The server turned down the new key, so the old one stays.
    case newKeyRefused(ConnectionFailure)
    /// The server's key or connection changed while it ran.
    case serverChanged
}
