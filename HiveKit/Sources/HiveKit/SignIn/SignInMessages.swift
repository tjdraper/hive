import Foundation

/// Times are given as seconds from now, so a device whose clock is off still knows how long it has.
public struct SignInChallenge: Codable, Sendable {
    public let challenge: Data
    public let expiresInSeconds: Int

    public init(challenge: Data, expiresInSeconds: Int) {
        self.challenge = challenge
        self.expiresInSeconds = expiresInSeconds
    }
}

public struct SignInRequest: Codable, Sendable {
    public let deviceID: UUID
    public let challenge: Data
    /// The raw form of a P-256 ECDSA signature over `SignInStatement`.
    public let signature: Data
    public let apiVersions: APIVersions

    public init(deviceID: UUID, challenge: Data, signature: Data, apiVersions: APIVersions) {
        self.deviceID = deviceID
        self.challenge = challenge
        self.signature = signature
        self.apiVersions = apiVersions
    }
}

public struct SignInSession: Codable, Sendable {
    /// Sent as `Authorization: Bearer <token>` on every request, live updates included.
    public let token: String
    public let expiresInSeconds: Int
    public let hiveAPIVersions: APIVersions

    public init(token: String, expiresInSeconds: Int, hiveAPIVersions: APIVersions) {
        self.token = token
        self.expiresInSeconds = expiresInSeconds
        self.hiveAPIVersions = hiveAPIVersions
    }
}

/// Sent with 409 Conflict instead of a session when the two can't work together.
public struct APIVersionMismatch: Codable, Sendable {
    public let update: OutdatedApp
    public let hiveAPIVersions: APIVersions

    public init(update: OutdatedApp, hiveAPIVersions: APIVersions) {
        self.update = update
        self.hiveAPIVersions = hiveAPIVersions
    }
}
