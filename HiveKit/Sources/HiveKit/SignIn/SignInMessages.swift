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
    /// Nil from a Beekeeper from before builds were reported.
    public let build: BeekeeperBuild?

    public init(deviceID: UUID, challenge: Data, signature: Data, apiVersions: APIVersions, build: BeekeeperBuild?) {
        self.deviceID = deviceID
        self.challenge = challenge
        self.signature = signature
        self.apiVersions = apiVersions
        self.build = build
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID, challenge, signature, apiVersions, build
    }

    /// A build this Hive can't read, such as one from a platform added later, is left out rather than
    /// turning the sign-in down.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decode(UUID.self, forKey: .deviceID)
        challenge = try container.decode(Data.self, forKey: .challenge)
        signature = try container.decode(Data.self, forKey: .signature)
        apiVersions = try container.decode(APIVersions.self, forKey: .apiVersions)
        build = (try? container.decodeIfPresent(BeekeeperBuild.self, forKey: .build))
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
