#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Sent by Scout to `ScoutEndpoint.enrollment`, over a connection pinned to the key in its code.
public struct ScoutEnrollmentRequest: Codable, Sendable {
    public let token: Data
    /// The X9.63 form of the P-256 key the Scout made for this enrollment.
    public let scoutPublicKey: Data
    public let protocolVersion: Int

    public init(token: Data, scoutPublicKey: Data, protocolVersion: Int) {
        self.token = token
        self.scoutPublicKey = scoutPublicKey
        self.protocolVersion = protocolVersion
    }
}

/// What a Scout needs to sign in to the Hive it just enrolled with, besides the pin and addresses,
/// which it already has from the code.
public struct ScoutEnrollment: Codable, Hashable, Sendable {
    public let hiveID: UUID
    public let serverID: UUID
    public let scoutID: UUID

    public init(hiveID: UUID, serverID: UUID, scoutID: UUID) {
        self.hiveID = hiveID
        self.serverID = serverID
        self.scoutID = scoutID
    }
}
