import CryptoKit
import Foundation
import HiveKit
import os

/// Checks the confirmation a request carries: a nonce Hive issued, unused and unexpired, signed with
/// the device's key over exactly this request (`ConfirmationStatement`). A session alone never confirms
/// anything, and a signature is good for one request only.
struct ConfirmationVerifier: Sendable {
    /// Long enough to read what the change will do and answer Touch ID or the password prompt.
    static let nonceLifetime: TimeInterval = 5 * 60

    /// Which of the device's keys signs.
    enum Signer {
        /// Its `.userPresence` key, for every confirmed change.
        case confirmationKey
        /// Its sign-in key, only to register its confirmation key.
        case signInKey
    }

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Confirmation")

    let hiveID: UUID
    let keys: ConfirmationKeyStore
    let devices: DeviceStore
    let nonces: IssuedChallenges
    let now: @Sendable () -> Date

    init(hiveID: UUID, database: HiveDatabase, now: @escaping @Sendable () -> Date) {
        self.hiveID = hiveID
        keys = ConfirmationKeyStore(database: database)
        devices = DeviceStore(database: database)
        nonces = IssuedChallenges(lifetime: Self.nonceLifetime)
        self.now = now
    }

    func issue() -> ConfirmationChallenge {
        let issued = nonces.issue(at: now())
        return ConfirmationChallenge(nonce: issued.challenge, expiresInSeconds: issued.expiresInSeconds)
    }

    /// False when the request carries no confirmation, which is fine for a change that doesn't need one.
    /// Throws `ConfirmationError.refused` for one that's there but no good. A good one uses up its nonce.
    func verify(
        _ proof: ConfirmationProof?,
        method: String,
        path: String,
        body: Data,
        deviceID: UUID,
        signer: Signer = .confirmationKey
    ) throws -> Bool {
        guard let proof else { return false }
        let now = now()
        switch nonces.check(proof.nonce, at: now) {
        case .valid: break
        case .expired: throw refuse(.nonceExpired)
        case .notIssued: throw refuse(.nonceNotIssued)
        }

        let keyData: Data?
        switch signer {
        case .confirmationKey: keyData = try keys.key(ofDevice: deviceID)
        case .signInKey: keyData = try devices.device(id: deviceID)?.publicKey
        }
        guard let keyData else { throw refuse(.noConfirmationKey) }

        let statement = ConfirmationStatement.bytes(
            hiveID: hiveID,
            deviceID: deviceID,
            nonce: proof.nonce,
            request: ConfirmationStatement.Request(method: method, path: path, body: body)
        )
        guard let publicKey = try? P256.Signing.PublicKey(x963Representation: keyData),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: proof.signature),
              publicKey.isValidSignature(signature, for: statement)
        else { throw refuse(.badSignature) }

        guard nonces.use(proof.nonce, at: now) else { throw refuse(.nonceReused) }
        Self.logger.notice("A device confirmed a request")
        return true
    }

    private func refuse(_ reason: ConfirmationRefusalReason) -> ConfirmationError {
        Self.logger.error("Refused a confirmation: \(reason.rawValue, privacy: .public)")
        return .refused(reason)
    }
}
