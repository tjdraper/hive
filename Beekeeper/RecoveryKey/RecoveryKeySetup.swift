import CryptoKit
import Foundation
import HiveKit
import Observation

/// Giving a Hive its recovery key: a new key made on this device and shown once, and its public half
/// given to Hive when the person says they've saved it. Until then the Hive has no key, so cancelling
/// leaves it as it was, and the key shown is never seen again.
@Observable
final class RecoveryKeySetup {
    let key = RecoveryKey()
    private(set) var isSaving = false
    private(set) var failure: String?

    /// Saves the key's public half with Touch ID or the password. Returns the Hive's answer once it's
    /// saved, or nil when it isn't.
    func save(on link: HiveLink, hiveName: String) async -> RecoveryKeyState? {
        isSaving = true
        defer { isSaving = false }
        do {
            let state: RecoveryKeyState = try await link.confirmed(
                "PUT",
                HiveEndpoint.recoveryKey,
                body: RecoveryKeyChange(publicKey: key.publicKey.rawRepresentation),
                reason: "save the recovery key for “\(hiveName)”"
            )
            failure = nil
            return state
        } catch ConfirmationKeyError.cancelled {
            return nil
        } catch {
            failure = HiveLink.message(for: error)
            return nil
        }
    }
}
