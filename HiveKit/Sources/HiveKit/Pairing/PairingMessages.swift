import Foundation

/// An open pairing window, as the device that opened it shows it.
public struct PairingWindow: Codable, Hashable, Sendable {
    public let id: UUID
    /// `PairingCode.text`, for the QR code and for copying. Hive never gives it out again.
    public let code: String
    public let expiresInSeconds: Int

    public init(id: UUID, code: String, expiresInSeconds: Int) {
        self.id = id
        self.code = code
        self.expiresInSeconds = expiresInSeconds
    }
}

/// The latest pairing window, so the device that opened it can tell when it's been used.
public enum PairingWindowState: Codable, Hashable, Sendable {
    /// None has been opened since Hive started, or the last one expired or was closed.
    case closed
    case open(id: UUID, expiresInSeconds: Int)
    case used(id: UUID, deviceID: UUID, deviceName: String)
}

/// Sent with 422 when Hive won't open a pairing window.
public struct PairingWindowRefusal: Codable, Hashable, Sendable {
    public let problem: PairingWindowProblem

    public init(problem: PairingWindowProblem) {
        self.problem = problem
    }
}

public enum PairingWindowProblem: String, Codable, Hashable, Sendable {
    /// A pairing code without an address would give the new device nowhere to reach the Hive.
    case noAddressOptions
}

/// Sent by a new device to `HiveEndpoint.pairing`, over a connection pinned to the key in the code.
public struct PairingRequest: Codable, Sendable {
    public let token: Data
    /// The X9.63 form of the P-256 key this device created for the Hive.
    public let devicePublicKey: Data
    public let deviceName: String
    public let apiVersions: APIVersions

    public init(token: Data, devicePublicKey: Data, deviceName: String, apiVersions: APIVersions) {
        self.token = token
        self.devicePublicKey = devicePublicKey
        self.deviceName = deviceName
        self.apiVersions = apiVersions
    }
}

/// Everything a device needs to sign in to the Hive it just paired with, besides the pin, which it
/// already has from the code.
public struct PairingResult: Codable, Hashable, Sendable {
    public let hiveID: UUID
    public let deviceID: UUID
    public let hiveName: String
    public let addresses: HiveAddresses

    public init(hiveID: UUID, deviceID: UUID, hiveName: String, addresses: HiveAddresses) {
        self.hiveID = hiveID
        self.deviceID = deviceID
        self.hiveName = hiveName
        self.addresses = addresses
    }
}
