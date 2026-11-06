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
