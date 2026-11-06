import Foundation

/// A paired device, as the device list shows it. Its key stays in Hive.
public struct DeviceSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let pairedAt: Date
    /// When it last signed in.
    public let lastSeenAt: Date?

    public init(id: UUID, name: String, pairedAt: Date, lastSeenAt: Date?) {
        self.id = id
        self.name = name
        self.pairedAt = pairedAt
        self.lastSeenAt = lastSeenAt
    }
}
