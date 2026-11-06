#if os(macOS)
import Foundation
import HiveKit
import Observation
import os

/// Pairing with this Mac's Hive and signing in to it. The pairing lasts only as long as Beekeeper runs,
/// since there's no list of Hives to keep it in.
@Observable
final class LocalHiveStore {
    enum State: Equatable {
        case notPaired
        case pairing
        case signingIn
        case signedIn(hiveID: UUID)
        case failed(String)
    }

    private static let logger = Logger(subsystem: BeekeeperLog.subsystem, category: "SignIn")

    private(set) var state = State.notPaired
    private let keychain = DeviceKeychain()

    func pairAndSignIn() async {
        state = .pairing
        let pairing: LocalPairing
        do {
            pairing = try await LocalPairingWorkflow(keychain: keychain).pair()
        } catch {
            state = .failed(Self.message(for: error))
            return
        }

        state = .signingIn
        do {
            guard let credential = try keychain.credential(for: pairing.hiveID) else {
                state = .failed("Beekeeper couldn't find the key it just made for this Hive.")
                return
            }
            let connection = HiveConnection(address: HiveAddress(host: "127.0.0.1", port: pairing.port), pin: pairing.pin)
            _ = try await connection.signIn(hiveID: credential.hiveID, deviceID: credential.deviceID, key: try credential.signingKey())
            Self.logger.notice("Signed in to this Mac's Hive")
            state = .signedIn(hiveID: pairing.hiveID)
        } catch {
            Self.logger.error("Couldn't sign in to this Mac's Hive: \(String(describing: error), privacy: .public)")
            state = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case LocalPairingError.unreachable:
            "Couldn't reach this Mac's Hive. Check that it's turned on in Hive."
        case LocalPairingError.refused(.notBeekeeper):
            "This Mac's Hive only pairs with Beekeeper signed by the same developer."
        case LocalPairingError.refused(let refusal):
            "This Mac's Hive turned down the pairing (\(refusal.rawValue))."
        case HiveConnectionError.wrongKey:
            "This Mac's Hive didn't show the key it paired with."
        case HiveConnectionError.signInRefused:
            "This Mac's Hive turned down the sign-in."
        case HiveConnectionError.lockedOut:
            "Too many failed sign-ins. Try again in 15 minutes."
        case HiveConnectionError.incompatible(update: .hive):
            "Update Hive to work with this Beekeeper."
        case HiveConnectionError.incompatible(update: .beekeeper):
            "Update Beekeeper to work with this Hive."
        case DeviceKeyError.secureEnclaveUnavailable:
            "This Mac has no Secure Enclave for Beekeeper's key."
        default:
            "Something went wrong: \(error.localizedDescription)"
        }
    }
}
#endif
