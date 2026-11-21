#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Times are given as seconds from now, so a server whose clock is off still knows how long it has.
public struct ScoutSignInChallenge: Codable, Sendable {
    public let challenge: Data
    public let expiresInSeconds: Int

    public init(challenge: Data, expiresInSeconds: Int) {
        self.challenge = challenge
        self.expiresInSeconds = expiresInSeconds
    }
}

public struct ScoutSignInRequest: Codable, Sendable {
    public let scoutID: UUID
    public let challenge: Data
    /// The raw form of a P-256 ECDSA signature over `ScoutSignInStatement`.
    public let signature: Data
    public let protocolVersion: Int
    /// Scout's own version, such as "0.1.0".
    public let scoutVersion: String
    /// The system and CPU it was built for, such as "linux-x86_64".
    public let platform: String

    public init(scoutID: UUID, challenge: Data, signature: Data, protocolVersion: Int, scoutVersion: String, platform: String) {
        self.scoutID = scoutID
        self.challenge = challenge
        self.signature = signature
        self.protocolVersion = protocolVersion
        self.scoutVersion = scoutVersion
        self.platform = platform
    }
}

public struct ScoutSession: Codable, Sendable {
    /// Sent as `Authorization: Bearer <token>` on every request to a Scout route.
    public let token: String
    public let expiresInSeconds: Int

    public init(token: String, expiresInSeconds: Int) {
        self.token = token
        self.expiresInSeconds = expiresInSeconds
    }
}

/// What a Scout's session is for.
public struct ScoutSessionCheck: Codable, Hashable, Sendable {
    public let serverID: UUID

    public init(serverID: UUID) {
        self.serverID = serverID
    }
}

/// What a Scout signs to sign in. It names the Hive and the Scout as well as the challenge, and its
/// label differs from a device's, so a signature can only ever mean this Scout signing in to this Hive.
public enum ScoutSignInStatement {
    private static let label = Data("Hive Scout sign-in v1".utf8)

    public static func bytes(hiveID: UUID, scoutID: UUID, challenge: Data) -> Data {
        var bytes = label
        bytes.append(0)
        withUnsafeBytes(of: hiveID.uuid) { bytes.append(contentsOf: $0) }
        withUnsafeBytes(of: scoutID.uuid) { bytes.append(contentsOf: $0) }
        bytes.append(challenge)
        return bytes
    }
}

/// Sent with 409 when Hive no longer accepts the Scout's protocol version, so it has to be updated.
public struct ScoutProtocolMismatch: Codable, Sendable {
    public let hiveProtocolVersion: Int

    public init(hiveProtocolVersion: Int) {
        self.hiveProtocolVersion = hiveProtocolVersion
    }
}
