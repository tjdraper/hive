import CryptoKit
import Foundation

/// The start of a recovery file (§14): what it is, and which recovery key it was written for. Hive
/// writes and opens the files. Beekeeper reads only this, to tell a copy made with an older key.
public enum RecoveryFileHeader {
    public static let fileExtension = "hiverecovery"
    public static let magic = Data("Hive recovery file".utf8)
    public static let version1: UInt8 = 1
    /// Of the raw X25519 public key.
    public static let keyLength = 32

    static var keyStart: Int {
        magic.count + 1
    }

    /// The raw public half of the recovery key `file` was written for, or nil when it isn't a recovery
    /// file this build can read.
    public static func publicKey(of file: Data) -> Data? {
        let bytes = Data(file)
        guard bytes.starts(with: magic), bytes.count >= keyStart + keyLength, bytes[magic.count] == version1 else { return nil }
        return bytes.subdata(in: keyStart ..< keyStart + keyLength)
    }

    /// Compared with `RecoveryKeyState.fileDigest` to tell whether a copy is the Hive's latest.
    public static func digest(of file: Data) -> Data {
        Data(SHA256.hash(data: file))
    }
}
