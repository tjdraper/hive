import Foundation
import GRDB
import HiveKit

/// A device that can sign in. Every paired device has full access.
public struct PairedDevice: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "device"

    public let id: UUID
    public let name: String
    /// The X9.63 form of the P-256 key the device created for this Hive.
    public let publicKey: Data
    public let pairedAt: Date
    public var lastSeenAt: Date?
    /// What it reported when it last signed in. Kept as JSON, which GRDB does for a property that isn't
    /// a database value.
    public var build: BeekeeperBuild?
    /// The latest warning opened about `build`, so each goes out once however often Hive checks.
    var buildWarning: BuildExpiryWarning?
}
