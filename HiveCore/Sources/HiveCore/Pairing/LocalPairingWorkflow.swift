import CryptoKit
import Foundation
import HiveKit
import os

/// Pairs Beekeeper on the Hive Mac, which `LocalPairingListener` has already confirmed is the sender.
/// Hive records the device's key and name, and answers with what the device needs to sign in.
public struct LocalPairingWorkflow: Sendable {
    /// Long enough for any name a person gives a Mac, short enough to list.
    static let longestDeviceName = 100

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Pairing")

    let hiveID: UUID
    let pin: PublicKeyPin
    let port: Int
    let devices: DeviceStore
    let now: @Sendable () -> Date

    public init(hiveID: UUID, pin: PublicKeyPin, port: Int, devices: DeviceStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.hiveID = hiveID
        self.pin = pin
        self.port = port
        self.devices = devices
        self.now = now
    }

    public func pair(_ request: LocalPairingRequest) -> LocalPairingResult {
        guard let publicKey = try? P256.Signing.PublicKey(x963Representation: request.devicePublicKey) else {
            return refuse(.invalidKey)
        }
        guard let name = Self.deviceName(from: request.deviceName) else { return refuse(.invalidName) }

        let device: PairedDevice
        do {
            device = try devices.add(name: name, publicKey: publicKey.x963Representation, at: now())
        } catch DeviceStoreError.alreadyPaired {
            return refuse(.alreadyPaired)
        } catch {
            Self.logger.error("Couldn't record a paired device: \(String(describing: error), privacy: .public)")
            return refuse(.hiveUnavailable)
        }

        Self.logger.notice("Paired Beekeeper on this Mac")
        return .paired(LocalPairing(hiveID: hiveID, deviceID: device.id, pin: pin, port: port))
    }

    func refuse(_ refusal: LocalPairingRefusal) -> LocalPairingResult {
        Self.logger.error("Refused to pair: \(refusal.rawValue, privacy: .public)")
        return .refused(refusal)
    }

    static func deviceName(from requested: String) -> String? {
        let name = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.count <= longestDeviceName,
              !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { return nil }
        return name
    }
}
