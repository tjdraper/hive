import Foundation

/// MySQL and MariaDB share a kind.
public enum DatabaseKind: String, Codable, Hashable, Sendable, CaseIterable {
    case mysql
    case postgres
}

public enum DatabaseLocation: Codable, Hashable, Sendable {
    /// Running on the server itself.
    case host
    /// In a Docker container, found by its Swarm or Compose service name. Exactly one running container must match.
    case container(serviceName: String)
}

/// Everything about a database a job dumps but its password.
public struct DatabaseSettings: Codable, Hashable, Sendable {
    public var kind: DatabaseKind
    public var location: DatabaseLocation
    public var user: String
    /// The database's own name, which also names its dump in each snapshot.
    public var name: String

    public init(kind: DatabaseKind, location: DatabaseLocation, user: String, name: String) {
        self.kind = kind
        self.location = location
        self.user = user
        self.name = name
    }
}

/// A database as Hive describes it. Its password stays in Hive.
public struct BackupDatabase: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let settings: DatabaseSettings
    public let hasPassword: Bool

    public init(id: UUID, settings: DatabaseSettings, hasPassword: Bool) {
        self.id = id
        self.settings = settings
        self.hasPassword = hasPassword
    }
}

/// A database as Beekeeper sends it within a job.
public struct BackupDatabaseDraft: Codable, Hashable, Sendable {
    /// Nil for a database being added. An existing database keeps its ID, and with it its password.
    public var id: UUID?
    public var settings: DatabaseSettings
    /// A new password, or nil to keep the one already set.
    public var password: String?

    public init(id: UUID?, settings: DatabaseSettings, password: String?) {
        self.id = id
        self.settings = settings
        self.password = password
    }
}

// So printing or logging a draft can't show its password.
extension BackupDatabaseDraft: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "BackupDatabaseDraft(id: \(id?.uuidString ?? "nil"), settings: \(settings), password: \(password == nil ? "nil" : "<set>"))"
    }

    public var debugDescription: String {
        description
    }
}
