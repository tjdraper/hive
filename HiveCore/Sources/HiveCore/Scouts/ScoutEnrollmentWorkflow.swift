import CryptoKit
import Foundation
import os
import ScoutProtocol

enum ScoutEnrollmentOutcome: Equatable {
    case enrolled(ScoutEnrollment)
    /// Answered as if the endpoint weren't there, so nobody without a good token learns anything.
    case refused(ScoutEnrollmentRefusal)
    /// The token was good, but the Scout's key wasn't. The window stays open, unless it was used up.
    case invalid(ScoutEnrollmentRefusal)
    case lockedOut
    /// Hive doesn't accept the Scout's protocol version. The window stays open for an updated Scout.
    case incompatible
}

/// Why enrolling failed. Logged, and never told to the Scout.
enum ScoutEnrollmentRefusal: String, Equatable {
    case noWindow = "no enrollment window open"
    case expired = "enrollment window expired"
    case wrongToken = "wrong token"
    case restarting = "Hive is restarting"
    case serverRemoved = "server removed"
    case openerRevoked = "the device that opened the window was revoked"
    case invalidKey = "invalid key"
    case keyInUse = "key already enrolled"
    case storeUnavailable = "store unavailable"
}

/// A Scout enrolling through its server's open window with the token from its code, over a connection
/// pinned to the key in the same code. It shares the pairing endpoint and its lockout with devices, but
/// a token opens only the kind of window it came from.
struct ScoutEnrollmentWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Scouts")

    let hiveID: UUID
    let scouts: ScoutStore
    let windows: EnrollmentWindowStore
    let sessions: SessionStore
    let limiter: FailedAttemptLimiter<ClientAddress>
    let isRestarting: @Sendable () -> Bool
    let now: @Sendable () -> Date

    func enroll(_ request: ScoutEnrollmentRequest, from address: ClientAddress) -> ScoutEnrollmentOutcome {
        let now = now()
        guard !limiter.isLockedOut(address, at: now) else {
            Self.logger.error("Refused to enroll a Scout from a locked-out address")
            return .lockedOut
        }
        if let refusal = tokenRefusal(request.token, at: now) { return refuse(refusal, address: address, at: now) }

        // Checked before the token is used up, so a Scout that sent something wrong can try again.
        guard let publicKey = try? P256.Signing.PublicKey(x963Representation: request.scoutPublicKey) else {
            return invalid(.invalidKey)
        }
        guard ScoutProtocolVersion.isAccepted(request.protocolVersion) else {
            Self.logger.error("Refused to enroll a Scout on protocol version \(request.protocolVersion, privacy: .public)")
            return .incompatible
        }
        guard let window = windows.claim(request.token, at: now) else { return refuse(.wrongToken, address: address, at: now) }
        defer { windows.finish(window) }
        return record(publicKey, through: window, from: address, at: now)
    }

    /// Nil when the token opens a window.
    private func tokenRefusal(_ token: Data, at now: Date) -> ScoutEnrollmentRefusal? {
        // A code issued before a new identity carries the old key's pin.
        guard !isRestarting() else { return .restarting }
        switch windows.check(token, at: now) {
        case .valid: return nil
        case .noWindow: return .noWindow
        case .expired: return .expired
        case .wrongToken: return .wrongToken
        }
    }

    private func record(
        _ publicKey: P256.Signing.PublicKey,
        through window: EnrollmentWindowStore.Window,
        from address: ClientAddress,
        at now: Date
    ) -> ScoutEnrollmentOutcome {
        let scout: ScoutRecord
        let replacedAnother: Bool
        do {
            (scout, replacedAnother) = try scouts.enroll(
                serverID: window.serverID,
                publicKey: publicKey.x963Representation,
                at: now,
                openedBy: window.openedBy
            )
        } catch ScoutStoreError.noServer {
            return refuse(.serverRemoved, address: address, at: now)
        } catch AuditLogError.unknownDevice {
            return refuse(.openerRevoked, address: address, at: now)
        } catch ScoutStoreError.keyInUse {
            return invalid(.keyInUse)
        } catch {
            Self.logger.error("Couldn't record an enrolled Scout: \(String(describing: error), privacy: .public)")
            return invalid(.storeUnavailable)
        }

        // The Scout it replaced, if any, can't send any more.
        sessions.endScoutSessions(forServer: window.serverID)
        limiter.reset(address)
        Self.logger.notice("A Scout enrolled (replaced another: \(replacedAnother, privacy: .public))")
        return .enrolled(ScoutEnrollment(hiveID: hiveID, serverID: window.serverID, scoutID: scout.id))
    }

    private func refuse(_ refusal: ScoutEnrollmentRefusal, address: ClientAddress, at now: Date) -> ScoutEnrollmentOutcome {
        if refusal != .restarting { limiter.recordFailure(address, at: now) }
        Self.logger.error("Refused to enroll a Scout: \(refusal.rawValue, privacy: .public)")
        return .refused(refusal)
    }

    private func invalid(_ refusal: ScoutEnrollmentRefusal) -> ScoutEnrollmentOutcome {
        Self.logger.error("Refused to enroll a Scout: \(refusal.rawValue, privacy: .public)")
        return .invalid(refusal)
    }
}
