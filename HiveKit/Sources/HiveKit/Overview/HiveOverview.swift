import Foundation

public struct HiveOverview: Codable, Hashable, Sendable {
    public let hiveID: UUID
    public let name: String
    public let fullDiskAccess: FullDiskAccessStatus
    public let macSleep: MacSleep
    public let addresses: HiveAddresses
    /// Optional, so Beekeeper still reads the overview from a Hive that doesn't send it.
    public let version: ReleaseVersion?

    public init(
        hiveID: UUID,
        name: String,
        fullDiskAccess: FullDiskAccessStatus,
        macSleep: MacSleep,
        addresses: HiveAddresses,
        version: ReleaseVersion?
    ) {
        self.hiveID = hiveID
        self.name = name
        self.fullDiskAccess = fullDiskAccess
        self.macSleep = macSleep
        self.addresses = addresses
        self.version = version
    }
}

/// Whether the Hive Mac is set to sleep when idle. Hive keeps it awake while a job runs, but a Mac
/// asleep at a scheduled time runs that job late, once it wakes.
public enum MacSleep: Codable, Hashable, Sendable {
    case never
    case afterIdle(minutes: Int)
    /// Hive couldn't read the setting.
    case unknown
}

/// A daemon can't ask for Full Disk Access, so Beekeeper warns while Hive doesn't have it.
public enum FullDiskAccessStatus: String, Codable, Hashable, Sendable {
    case granted
    case missing
    /// Hive couldn't tell, which it treats as missing.
    case unknown
}
