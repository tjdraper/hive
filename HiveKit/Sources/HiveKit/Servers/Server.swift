import Foundation

/// A machine Hive backs up, entered once, with a backup job for each site on it.
public struct Server: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let connection: ServerConnection
    /// The most space its jobs' snapshots may take on the backup drive, in bytes. Nil for no limit.
    public let quotaBytes: Int64?
    /// Hive connects only once a device has confirmed the server's host key. Changing the connection clears it.
    public let confirmedHostKey: HostKeyFingerprint?
    /// The fingerprint of Hive's SSH key for this server. Nil for a server added before Hive made keys.
    public let sshKeyFingerprint: String?

    public init(
        id: UUID,
        name: String,
        connection: ServerConnection,
        quotaBytes: Int64?,
        confirmedHostKey: HostKeyFingerprint?,
        sshKeyFingerprint: String?
    ) {
        self.id = id
        self.name = name
        self.connection = connection
        self.quotaBytes = quotaBytes
        self.confirmedHostKey = confirmedHostKey
        self.sshKeyFingerprint = sshKeyFingerprint
    }

    /// The server as it would be sent back unchanged, to start an edit from.
    public var draft: ServerDraft {
        ServerDraft(name: name, connection: connection, quotaBytes: quotaBytes)
    }
}

/// Where Hive connects with SSH. Changing any of it clears the server's database passwords and its
/// confirmed host key, so a secret is never sent somewhere new without being entered again.
public struct ServerConnection: Codable, Hashable, Sendable {
    public var host: String
    public var port: Int
    public var user: String

    public init(host: String, port: Int = 22, user: String) {
        self.host = host
        self.port = port
        self.user = user
    }
}

/// A server as Beekeeper sends it, to add one or to change one whole.
public struct ServerDraft: Codable, Hashable, Sendable {
    public var name: String
    public var connection: ServerConnection
    public var quotaBytes: Int64?

    public init(name: String, connection: ServerConnection, quotaBytes: Int64?) {
        self.name = name
        self.connection = connection
        self.quotaBytes = quotaBytes
    }
}
