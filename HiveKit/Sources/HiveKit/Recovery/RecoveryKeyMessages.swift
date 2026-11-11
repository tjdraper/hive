import Foundation

/// Whether the Hive has a recovery key, and its latest recovery file written with it.
public struct RecoveryKeyState: Codable, Hashable, Sendable {
    /// When the current key was saved. Nil while the Hive has none, so it writes no recovery files.
    public let keySavedAt: Date?
    /// The raw X25519 public half of the current key, which a copy's `RecoveryFileHeader` is compared
    /// with to tell one made with an older key.
    public let publicKey: Data?
    /// When the recovery file in the Hive's data directory was last written with the current key.
    public let fileWrittenAt: Date?
    /// `RecoveryFileHeader.digest(of:)` of that file.
    public let fileDigest: Data?

    public init(keySavedAt: Date?, publicKey: Data?, fileWrittenAt: Date?, fileDigest: Data?) {
        self.keySavedAt = keySavedAt
        self.publicKey = publicKey
        self.fileWrittenAt = fileWrittenAt
        self.fileDigest = fileDigest
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

/// The Hive's latest recovery file, for a device to keep a copy of (§14). Only its recovery key opens
/// it, and Hive holds only that key's public half.
public struct RecoveryFileDownload: Codable, Hashable, Sendable {
    public let file: Data

    public init(file: Data) {
        self.file = file
    }
}
