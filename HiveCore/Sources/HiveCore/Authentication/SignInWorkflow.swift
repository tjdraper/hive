import CryptoKit
import Foundation
import HiveKit
import os

enum SignInOutcome: Equatable {
    case signedIn(token: String, expiresAt: Date)
    case refused(SignInRefusal)
    case lockedOut
    case incompatible(OutdatedApp)
}

/// Why a sign-in failed. Logged, and never told to the device, which only learns that it failed.
enum SignInRefusal: String, Equatable {
    case malformed
    case challengeNotIssued = "challenge not issued by this Hive"
    case challengeExpired = "challenge expired"
    case challengeReused = "challenge already used"
    case unknownDevice = "unknown or revoked device"
    case badSignature = "bad signature"
    case storeUnavailable = "store unavailable"
}

/// A device proves it holds its key by signing a fresh challenge, and gets a short-lived session.
/// The signature isn't bound to the TLS connection, because SwiftNIO's TLS doesn't expose the exporter
/// that needs. The key pin, the challenge's short life and single use, and the session's short life
/// protect it instead.
public struct SignInWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "SignIn")

    let hiveID: UUID
    let devices: DeviceStore
    let sessions: SessionStore
    let challenges: SignInChallenges
    let addressLimiter: FailedAttemptLimiter<ClientAddress>
    let deviceLimiter: FailedAttemptLimiter<UUID>
    let apiVersions: APIVersions
    let now: @Sendable () -> Date

    public init(hiveID: UUID, devices: DeviceStore, sessions: SessionStore) {
        self.init(hiveID: hiveID, devices: devices, sessions: sessions, apiVersions: .thisBuild, now: Date.init)
    }

    init(
        hiveID: UUID,
        devices: DeviceStore,
        sessions: SessionStore,
        apiVersions: APIVersions,
        now: @escaping @Sendable () -> Date
    ) {
        self.hiveID = hiveID
        self.devices = devices
        self.sessions = sessions
        challenges = SignInChallenges()
        addressLimiter = FailedAttemptLimiter(policy: .signIn)
        deviceLimiter = FailedAttemptLimiter(policy: .signIn)
        self.apiVersions = apiVersions
        self.now = now
    }

    func issueChallenge() -> SignInChallenge {
        challenges.issue(at: now())
    }

    func signIn(_ request: SignInRequest?, from address: ClientAddress) -> SignInOutcome {
        let now = now()
        guard !addressLimiter.isLockedOut(address, at: now) else { return lockOut("address") }
        guard let request else { return refuse(.malformed, address: address, at: now) }
        guard !deviceLimiter.isLockedOut(request.deviceID, at: now) else { return lockOut("device") }

        let device: PairedDevice
        switch verify(request, at: now) {
        case .success(let verified):
            device = verified
        case .failure(let failure):
            return refuse(failure.refusal, address: address, device: failure.deviceID, at: now)
        }

        addressLimiter.reset(address)
        deviceLimiter.reset(device.id)

        if let outdated = APIVersions.outdatedApp(hive: apiVersions, beekeeper: request.apiVersions) {
            Self.logger.error("Refused a sign-in from a device on another API version, update \(outdated.rawValue, privacy: .public)")
            return .incompatible(outdated)
        }

        do {
            try devices.recordSignIn(id: device.id, at: now)
        } catch {
            Self.logger.error("Couldn't record when a device was last seen: \(String(describing: error), privacy: .public)")
        }
        let session = sessions.start(for: device.id, at: now)
        Self.logger.notice("A device signed in")
        return .signedIn(token: session.token, expiresAt: session.expiresAt)
    }

    private struct VerificationFailure: Error {
        let refusal: SignInRefusal
        /// Set once the device is known, so its failures count against it as well as the address.
        var deviceID: UUID?
    }

    /// Checks the challenge, the device and its signature, then uses up the challenge.
    private func verify(_ request: SignInRequest, at now: Date) -> Result<PairedDevice, VerificationFailure> {
        switch challenges.check(request.challenge, at: now) {
        case .valid: break
        case .expired: return .failure(VerificationFailure(refusal: .challengeExpired))
        case .notIssued: return .failure(VerificationFailure(refusal: .challengeNotIssued))
        }

        let device: PairedDevice?
        do {
            device = try devices.device(id: request.deviceID)
        } catch {
            Self.logger.error("Couldn't read devices: \(String(describing: error), privacy: .public)")
            return .failure(VerificationFailure(refusal: .storeUnavailable))
        }
        guard let device else { return .failure(VerificationFailure(refusal: .unknownDevice)) }

        let statement = SignInStatement.bytes(hiveID: hiveID, deviceID: device.id, challenge: request.challenge)
        guard let publicKey = try? P256.Signing.PublicKey(x963Representation: device.publicKey),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: request.signature),
              publicKey.isValidSignature(signature, for: statement)
        else { return .failure(VerificationFailure(refusal: .badSignature, deviceID: device.id)) }

        guard challenges.use(request.challenge, at: now) else {
            return .failure(VerificationFailure(refusal: .challengeReused, deviceID: device.id))
        }
        return .success(device)
    }

    private func refuse(_ refusal: SignInRefusal, address: ClientAddress, device: UUID? = nil, at now: Date) -> SignInOutcome {
        // Hive's own failure says nothing about the sender.
        if refusal != .storeUnavailable {
            addressLimiter.recordFailure(address, at: now)
            if let device { deviceLimiter.recordFailure(device, at: now) }
        }
        Self.logger.error("Refused a sign-in: \(refusal.rawValue, privacy: .public)")
        return .refused(refusal)
    }

    private func lockOut(_ kind: String) -> SignInOutcome {
        Self.logger.error("Refused a sign-in from a locked-out \(kind, privacy: .public)")
        return .lockedOut
    }
}
