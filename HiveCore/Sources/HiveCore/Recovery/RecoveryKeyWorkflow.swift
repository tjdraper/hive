import CryptoKit
import Foundation
import HiveKit
import os

/// Giving the Hive its recovery key, or a new one (§14). Beekeeper makes the key and sends only its
/// public half, so the private half never reaches the Hive's Mac through Hive.
struct RecoveryKeyWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Recovery")

    let store: RecoveryKeyStore
    let files: RecoveryFileWriter
    let now: @Sendable () -> Date

    func state() throws -> RecoveryKeyState {
        try store.state()
    }

    /// Throws `ConfirmationError.required`, changing nothing, unless confirmed. The file written with an
    /// old key is removed and one written with the new key.
    func save(_ key: Curve25519.KeyAgreement.PublicKey, isConfirmed: Bool, by deviceID: UUID) async throws -> RecoveryKeyState {
        try ConfirmationRequirement.check([.recoveryKeyChanged], isConfirmed: isConfirmed)
        switch try store.save(key, by: deviceID, at: now()) {
        case .unchanged:
            break
        case .saved(let replacedAnother):
            Self.logger.notice("Saved a recovery key (replaced another: \(replacedAnother, privacy: .public))")
            await files.startOver()
        }
        return try store.state()
    }
}
