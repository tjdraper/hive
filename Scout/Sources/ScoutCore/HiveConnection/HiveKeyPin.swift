import Crypto

/// The SHA-256 hash of Hive's identity key in its X9.63 form, the same pin Beekeeper keeps. It names
/// the key, not the certificate, so Hive can reissue its certificate without every Scout enrolling again.
public struct HiveKeyPin: Equatable, Sendable {
    public let sha256: [UInt8]

    public init(sha256: [UInt8]) {
        self.sha256 = sha256
    }

    public init?(hex: String) {
        guard hex.utf8.count == SHA256.byteCount * 2 else { return nil }
        // Digit by digit, since `UInt8(_:radix:)` also accepts a sign.
        var bytes: [UInt8] = []
        var digits = hex.makeIterator()
        while let high = digits.next()?.hexDigitValue, let low = digits.next()?.hexDigitValue {
            bytes.append(UInt8(high << 4 | low))
        }
        guard bytes.count == SHA256.byteCount else { return nil }
        sha256 = bytes
    }

    init(publicKey: P256.Signing.PublicKey) {
        sha256 = Array(SHA256.hash(data: publicKey.x963Representation))
    }

    /// Whether a certificate's key, in the DER `SubjectPublicKeyInfo` form, is the pinned one. A key
    /// that isn't P-256 never is.
    func matches(subjectPublicKeyInfo der: [UInt8]) -> Bool {
        guard let key = try? P256.Signing.PublicKey(derRepresentation: der) else { return false }
        return HiveKeyPin(publicKey: key) == self
    }
}
