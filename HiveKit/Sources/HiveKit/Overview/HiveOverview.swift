import Foundation

public struct HiveOverview: Codable, Hashable, Sendable {
    public let hiveID: UUID
    public let name: String
    public let fullDiskAccess: FullDiskAccessStatus

    public init(hiveID: UUID, name: String, fullDiskAccess: FullDiskAccessStatus) {
        self.hiveID = hiveID
        self.name = name
        self.fullDiskAccess = fullDiskAccess
    }
}

/// A daemon can't ask for Full Disk Access, so Beekeeper warns while Hive doesn't have it.
public enum FullDiskAccessStatus: String, Codable, Hashable, Sendable {
    case granted
    case missing
    /// Hive couldn't tell, which it treats as missing.
    case unknown
}
