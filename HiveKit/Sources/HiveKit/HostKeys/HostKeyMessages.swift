import Foundation

/// A server's SSH host key, as Beekeeper shows it for comparing with the server's own
/// `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`.
public struct HostKeyFingerprint: Codable, Hashable, Sendable {
    /// Such as `ssh-ed25519`.
    public let keyType: String
    /// SHA-256, as OpenSSH writes it: `SHA256:` and unpadded base64.
    public let fingerprint: String

    public init(keyType: String, fingerprint: String) {
        self.keyType = keyType
        self.fingerprint = fingerprint
    }
}

/// What scanning a server's host key found. The key isn't recorded until a device confirms it with
/// `HostKeyConfirmation`.
public enum HostKeyScanResult: Codable, Hashable, Sendable {
    case found(key: HostKeyFingerprint)
    case failed(reason: ConnectionFailure)
}

/// Sent to record the key the last scan found, once the person has checked its fingerprint.
public struct HostKeyConfirmation: Codable, Hashable, Sendable {
    public let fingerprint: String

    public init(fingerprint: String) {
        self.fingerprint = fingerprint
    }
}

/// Sent with 409 when Hive doesn't record a host key. Scanning again starts over.
public struct HostKeyConfirmationRefusal: Codable, Hashable, Sendable {
    public let reason: HostKeyConfirmationRefusalReason

    public init(reason: HostKeyConfirmationRefusalReason) {
        self.reason = reason
    }
}

public enum HostKeyConfirmationRefusalReason: String, Codable, Hashable, Sendable {
    /// No recent scan, or one made before the server's host, port or user changed.
    case noScan
    /// The fingerprint isn't the one the last scan found.
    case fingerprintMismatch
}
