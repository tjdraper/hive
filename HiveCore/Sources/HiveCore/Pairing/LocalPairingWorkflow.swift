import CryptoKit
import Foundation
import HiveKit
import os

/// Pairs Beekeeper on the Hive Mac, which `LocalPairingListener` has already confirmed is the sender.
/// Hive records the device's key and name, and answers with what the device needs to sign in.
public struct LocalPairingWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Pairing")

    let hiveID: UUID
    let pin: PublicKeyPin
    /// Read at each pairing, since the port can change while Hive runs.
    let settings: HiveSettingsStore
    let devices: DeviceStore
    let now: @Sendable () -> Date

    public init(
        hiveID: UUID,
        pin: PublicKeyPin,
        settings: HiveSettingsStore,
        devices: DeviceStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hiveID = hiveID
        self.pin = pin
        self.settings = settings
        self.devices = devices
        self.now = now
    }

    public func pair(_ request: LocalPairingRequest) -> LocalPairingResult {
        guard let publicKey = try? P256.Signing.PublicKey(x963Representation: request.devicePublicKey) else {
            return refuse(.invalidKey)
        }
        guard let name = DisplayName.validated(request.deviceName) else { return refuse(.invalidName) }

        let device: PairedDevice
        let port: Int
        do {
            port = try settings.settings().port
            device = try devices.add(name: name, publicKey: publicKey.x963Representation, at: now(), auditedAs: .pairedOnHiveMac)
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
}
