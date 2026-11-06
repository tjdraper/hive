import Foundation

/// Sent over XPC by Beekeeper on the Hive Mac, which is the only program Hive accepts it from.
public struct LocalPairingRequest: Codable, Sendable {
    /// The X9.63 form of the P-256 key this device created for the Hive.
    public let devicePublicKey: Data
    public let deviceName: String

    public init(devicePublicKey: Data, deviceName: String) {
        self.devicePublicKey = devicePublicKey
        self.deviceName = deviceName
    }
}

/// Everything a device needs to sign in to the Hive it just paired with.
public struct LocalPairing: Codable, Hashable, Sendable {
    public let hiveID: UUID
    public let deviceID: UUID
    public let pin: PublicKeyPin
    /// Hive's HTTPS port on `127.0.0.1`.
    public let port: Int

    public init(hiveID: UUID, deviceID: UUID, pin: PublicKeyPin, port: Int) {
        self.hiveID = hiveID
        self.deviceID = deviceID
        self.pin = pin
        self.port = port
    }
}

public enum LocalPairingRefusal: String, Codable, Sendable {
    /// The sender isn't Beekeeper signed by Hive's own team.
    case notBeekeeper
    case invalidRequest
    case invalidKey
    case invalidName
    case alreadyPaired
    case hiveUnavailable
}

public enum LocalPairingResult: Codable, Hashable, Sendable {
    case paired(LocalPairing)
    case refused(LocalPairingRefusal)
}
