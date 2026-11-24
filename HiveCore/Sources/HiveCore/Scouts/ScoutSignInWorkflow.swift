import CryptoKit
import Foundation
import os
import ScoutProtocol

enum ScoutSignInOutcome: Equatable {
    case signedIn(token: String, expiresAt: Date)
    case refused(SignInRefusal)
    case lockedOut
    /// Hive doesn't accept the Scout's protocol version, so it has to be updated.
    case incompatible
}

/// A Scout proves it holds its key by signing a challenge from the same route devices use, and gets a
/// short-lived session for its own server, which reaches only Scout's routes.
struct ScoutSignInWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "SignIn")
    /// Far longer than any version or platform Scout reports.
    static let longestReported = 32
    private static let reportedCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_+")

    let hiveID: UUID
    let scouts: ScoutStore
    let sessions: SessionStore
    let challenges: IssuedChallenges
    let addressLimiter: FailedAttemptLimiter<ClientAddress>
    let scoutLimiter: FailedAttemptLimiter<UUID>
    let now: @Sendable () -> Date

    func signIn(_ request: ScoutSignInRequest, from address: ClientAddress) -> ScoutSignInOutcome {
        let now = now()
        guard !addressLimiter.isLockedOut(address, at: now), !scoutLimiter.isLockedOut(request.scoutID, at: now) else {
            Self.logger.error("Refused a Scout's sign-in while locked out")
            return .lockedOut
        }

        let scout: ScoutRecord
        switch verify(request, at: now) {
        case .success(let verified):
            scout = verified
        case .failure(let failure):
            // Hive's own failure says nothing about the sender.
            if failure.refusal != .storeUnavailable {
                addressLimiter.recordFailure(address, at: now)
                if failure.isKnownScout { scoutLimiter.recordFailure(request.scoutID, at: now) }
            }
            Self.logger.error("Refused a Scout's sign-in: \(failure.refusal.rawValue, privacy: .public)")
            return .refused(failure.refusal)
        }
        addressLimiter.reset(address)
        scoutLimiter.reset(scout.id)

        // Recorded before the protocol is checked, so a Scout too old to sign in shows as out of date.
        do {
            try scouts.recordSignIn(
                id: scout.id,
                version: Self.validated(request.scoutVersion),
                platform: Self.validated(request.platform),
                protocolVersion: request.protocolVersion,
                at: now
            )
        } catch {
            Self.logger.error("Couldn't record when a Scout was last seen: \(String(describing: error), privacy: .public)")
        }

        guard ScoutProtocolVersion.isAccepted(request.protocolVersion) else {
            Self.logger.error("Refused a Scout on protocol version \(request.protocolVersion, privacy: .public)")
            return .incompatible
        }
        let session = sessions.start(for: .scout(SignedInScout(scoutID: scout.id, serverID: scout.serverID)), at: now)
        Self.logger.notice("A Scout signed in")
        return .signedIn(token: session.token, expiresAt: session.expiresAt)
    }

    private struct VerificationFailure: Error {
        let refusal: SignInRefusal
        var isKnownScout = false
    }

    private func verify(_ request: ScoutSignInRequest, at now: Date) -> Result<ScoutRecord, VerificationFailure> {
        switch challenges.check(request.challenge, at: now) {
        case .valid: break
        case .expired: return .failure(VerificationFailure(refusal: .challengeExpired))
        case .notIssued: return .failure(VerificationFailure(refusal: .challengeNotIssued))
        }

        let scout: ScoutRecord?
        do {
            scout = try scouts.scout(id: request.scoutID)
        } catch {
            Self.logger.error("Couldn't read Scouts: \(String(describing: error), privacy: .public)")
            return .failure(VerificationFailure(refusal: .storeUnavailable))
        }
        guard let scout else { return .failure(VerificationFailure(refusal: .unknownDevice)) }

        let statement = ScoutSignInStatement.bytes(hiveID: hiveID, scoutID: scout.id, challenge: request.challenge)
        guard let publicKey = try? P256.Signing.PublicKey(x963Representation: scout.publicKey),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: request.signature),
              publicKey.isValidSignature(signature, for: statement)
        else { return .failure(VerificationFailure(refusal: .badSignature, isKnownScout: true)) }

        guard challenges.use(request.challenge, at: now) else {
            return .failure(VerificationFailure(refusal: .challengeReused, isKnownScout: true))
        }
        return .success(scout)
    }

    /// What a Scout reports is stored and shown, so it's checked first. One that fails is left out, and
    /// the sign-in goes ahead.
    private static func validated(_ text: String) -> String? {
        guard !text.isEmpty, text.count <= longestReported, text.allSatisfy(reportedCharacters.contains) else { return nil }
        return text
    }
}
