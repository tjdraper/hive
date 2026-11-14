import Foundation

/// A paired device, as the device list shows it. Its key stays in Hive.
public struct DeviceSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let pairedAt: Date
    /// When it last signed in.
    public let lastSeenAt: Date?
    /// The build it reported when it last signed in.
    public let build: BeekeeperBuild?

    public init(id: UUID, name: String, pairedAt: Date, lastSeenAt: Date?, build: BeekeeperBuild?) {
        self.id = id
        self.name = name
        self.pairedAt = pairedAt
        self.lastSeenAt = lastSeenAt
        self.build = build
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, pairedAt, lastSeenAt, build
    }

    /// A build this Beekeeper can't read, such as one from a platform added later, is left out rather
    /// than losing the whole list.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        pairedAt = try container.decode(Date.self, forKey: .pairedAt)
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        build = (try? container.decodeIfPresent(BeekeeperBuild.self, forKey: .build))
    }
}
