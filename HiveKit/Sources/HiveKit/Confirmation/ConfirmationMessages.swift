import Foundation

/// A nonce for one confirmation, from `HiveEndpoint.confirmationChallenge`. It can be used once.
public struct ConfirmationChallenge: Codable, Sendable {
    public let nonce: Data
    public let expiresInSeconds: Int

    public init(nonce: Data, expiresInSeconds: Int) {
        self.nonce = nonce
        self.expiresInSeconds = expiresInSeconds
    }
}

/// A device's confirmation of one request: a fresh nonce, and its confirmation key's signature over
/// `ConfirmationStatement`. Sent in the `Hive-Confirmation` header, so every request body stays as it is.
public struct ConfirmationProof: Hashable, Sendable {
    public static let headerName = "Hive-Confirmation"

    public let nonce: Data
    /// The raw form of a P-256 ECDSA signature.
    public let signature: Data

    public init(nonce: Data, signature: Data) {
        self.nonce = nonce
        self.signature = signature
    }

    /// Nil when it isn't two base64 values joined by a dot.
    public init?(headerValue: String) {
        let parts = headerValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let nonce = Data(base64Encoded: String(parts[0])),
              let signature = Data(base64Encoded: String(parts[1]))
        else { return nil }
        self.init(nonce: nonce, signature: signature)
    }

    public var headerValue: String {
        "\(nonce.base64EncodedString()).\(signature.base64EncodedString())"
    }
}

/// Registers the signed-in device's confirmation key, a second Secure Enclave key that asks for Touch ID
/// or the account password each time it signs. The request is confirmed by the device's sign-in key,
/// so a session token alone can't register one.
public struct ConfirmationKeyRegistration: Codable, Hashable, Sendable {
    /// The X9.63 form of a P-256 key.
    public let publicKey: Data

    public init(publicKey: Data) {
        self.publicKey = publicKey
    }
}

/// Why a change needs the device's confirmation key as well as its session: it sends a secret
/// somewhere new, deletes snapshots or leads to them being deleted, or unpairs every device.
public enum ConfirmationReason: String, Codable, CaseIterable, Hashable, Sendable {
    case connectionChanged
    case quotaLowered
    case retentionLowered
    case passwordReplaced
    case hostKeyReplaced
    case sshKeyReplaced
    case snapshotsDeleted
    case identityRegenerated
    case emailHostChanged
}

/// Sent with 428 when a change needs confirming and the request carried none.
public struct ConfirmationRequired: Codable, Hashable, Sendable {
    public let reasons: [ConfirmationReason]

    public init(reasons: [ConfirmationReason]) {
        self.reasons = reasons
    }
}

/// Sent with 403 when a request carried a confirmation Hive won't accept. Nothing was changed.
public struct ConfirmationRefusal: Codable, Hashable, Sendable {
    public let reason: ConfirmationRefusalReason

    public init(reason: ConfirmationRefusalReason) {
        self.reason = reason
    }
}

public enum ConfirmationRefusalReason: String, Codable, Hashable, Sendable {
    case malformed
    /// Not issued by this Hive since it last started.
    case nonceNotIssued
    case nonceExpired
    case nonceReused
    /// The device hasn't registered a confirmation key.
    case noConfirmationKey
    /// Not signed by the device's confirmation key over this request.
    case badSignature
    /// Registering a key when the device already has a different one. Pairing again starts over.
    case keyAlreadyRegistered
}
