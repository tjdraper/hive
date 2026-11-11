import Foundation

/// Whether the Hive has a recovery key, and when its recovery file was last written with it.
public struct RecoveryKeyState: Codable, Hashable, Sendable {
    /// When the current key was saved. Nil while the Hive has none, so it writes no recovery files.
    public let keySavedAt: Date?
    /// When the recovery file in the Hive's data directory was last written with the current key.
    public let fileWrittenAt: Date?

    public init(keySavedAt: Date?, fileWrittenAt: Date?) {
        self.keySavedAt = keySavedAt
        self.fileWrittenAt = fileWrittenAt
    }

    public var hasKey: Bool {
        keySavedAt != nil
    }
}

/// Gives the Hive a recovery key, or a new one in place of its old one. Always confirmed: whoever holds
/// the private half can open every secret in the Hive's recovery files.
public struct RecoveryKeyChange: Codable, Hashable, Sendable {
    /// The raw form of the X25519 public key, `RecoveryKey.publicKey`.
    public let publicKey: Data

    public init(publicKey: Data) {
        self.publicKey = publicKey
    }
}
