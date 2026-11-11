import CryptoKit
import Foundation
import HiveKit
import os

enum CodePairingOutcome: Equatable {
    case paired(PairingResult)
    /// Answered as if the endpoint weren't there, so nobody without a good token learns anything.
    case refused(CodePairingRefusal)
    /// The token was good, but the device's key or name wasn't. The window stays open.
    case invalid(CodePairingRefusal)
    case lockedOut
    case incompatible(OutdatedApp)
}

/// Why pairing through a code failed. Logged, and never told to the device.
enum CodePairingRefusal: String, Equatable {
    case malformed
    case noWindow = "no pairing window open"
    case expired = "pairing window expired"
    case wrongToken = "wrong token"
    case restarting = "Hive is restarting"
    case invalidKey = "invalid key"
    case invalidName = "invalid name"
    case alreadyPaired = "key already paired"
    case storeUnavailable = "store unavailable"
}

/// A new device pairing through the open window with the token from its code, which it reached over a
/// connection pinned to the key in the same code. The window closes once used, and repeated failures
/// lock out the address they came from.
struct CodePairingWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Pairing")

    let settings: HiveSettingsStore
    let devices: DeviceStore
    let windows: PairingWindowStore
    let limiter: FailedAttemptLimiter<ClientAddress>
    let apiVersions: APIVersions
    let hiveID: UUID
    let isRestarting: @Sendable () -> Bool
    let now: @Sendable () -> Date

    func pair(_ request: PairingRequest?, from address: ClientAddress) -> CodePairingOutcome {
        let now = now()
        guard !limiter.isLockedOut(address, at: now) else {
            Self.logger.error("Refused to pair a device from a locked-out address")
            return .lockedOut
        }
        guard let request else { return refuse(.malformed, address: address, at: now) }
        if let refusal = tokenRefusal(request.token, at: now) { return refuse(refusal, address: address, at: now) }

        // Checked before the token is used up, so a device that sent something wrong can try again.
        let device: NewDevice
        switch newDevice(in: request) {
        case .success(let valid): device = valid
        case .failure(let turnedDown): return turnedDown.outcome
        }
        guard let window = windows.claim(request.token, at: now) else { return refuse(.wrongToken, address: address, at: now) }
        return add(device, through: window, from: address, at: now)
    }

    private struct NewDevice {
        let publicKey: P256.Signing.PublicKey
        let name: String
    }

    private struct TurnedDown: Error {
        let outcome: CodePairingOutcome
    }

    /// Nil when the token opens the window.
    private func tokenRefusal(_ token: Data, at now: Date) -> CodePairingRefusal? {
        // A code issued before a new identity carries the old key's pin.
        guard !isRestarting() else { return .restarting }
        switch windows.check(token, at: now) {
        case .valid: return nil
        case .noWindow: return .noWindow
        case .expired: return .expired
        case .wrongToken: return .wrongToken
        }
    }

    private func newDevice(in request: PairingRequest) -> Result<NewDevice, TurnedDown> {
        guard let publicKey = try? P256.Signing.PublicKey(x963Representation: request.devicePublicKey) else {
            return .failure(TurnedDown(outcome: invalid(.invalidKey)))
        }
        guard let name = DisplayName.validated(request.deviceName) else { return .failure(TurnedDown(outcome: invalid(.invalidName))) }
        if let outdated = APIVersions.outdatedApp(hive: apiVersions, beekeeper: request.apiVersions) {
            Self.logger.error("Refused to pair a device on another API version, update \(outdated.rawValue, privacy: .public)")
            return .failure(TurnedDown(outcome: .incompatible(outdated)))
        }
        return .success(NewDevice(publicKey: publicKey, name: name))
    }

    private func add(
        _ new: NewDevice,
        through window: PairingWindowStore.Window,
        from address: ClientAddress,
        at now: Date
    ) -> CodePairingOutcome {
        let device: PairedDevice
        let current: HiveSettings
        do {
            current = try settings.settings()
            device = try devices.add(
                name: new.name,
                publicKey: new.publicKey.x963Representation,
                at: now,
                auditedAs: .pairedWithCode(openedBy: window.openedBy, openedByName: window.openedByName)
            )
        } catch DeviceStoreError.alreadyPaired {
            windows.abandon(window)
            return invalid(.alreadyPaired)
        } catch {
            windows.abandon(window)
            Self.logger.error("Couldn't record a paired device: \(String(describing: error), privacy: .public)")
            return invalid(.storeUnavailable)
        }

        windows.finish(window, pairing: device)
        limiter.reset(address)
        Self.logger.notice("Paired a device through a pairing code")
        return .paired(PairingResult(hiveID: hiveID, deviceID: device.id, hiveName: current.name, addresses: current.addresses))
    }

    private func refuse(_ refusal: CodePairingRefusal, address: ClientAddress, at now: Date) -> CodePairingOutcome {
        if refusal != .restarting { limiter.recordFailure(address, at: now) }
        Self.logger.error("Refused to pair a device: \(refusal.rawValue, privacy: .public)")
        return .refused(refusal)
    }

    private func invalid(_ refusal: CodePairingRefusal) -> CodePairingOutcome {
        Self.logger.error("Refused to pair a device: \(refusal.rawValue, privacy: .public)")
        return .invalid(refusal)
    }
}
