import CryptoKit
import Foundation
import HiveKit
import os

enum ConfirmationWorkflowError: Error, Equatable {
    case notPaired
    /// Hive has another confirmation key for this device, and this device has lost its own. Only pairing
    /// again starts over.
    case keyMismatch
}

/// Sends a request whose change may need confirming. With a `reason`, it asks the person first: Touch
/// ID or the password, then the request with a fresh nonce from Hive signed by this device's
/// confirmation key. Without one it sends the request as it is, and asks only if Hive answers that it
/// needs confirming, such as when another device changed something meanwhile.
struct ConfirmationWorkflow {
    private static let logger = Logger(subsystem: BeekeeperLog.subsystem, category: "Confirmation")

    let hiveID: UUID
    let keychain: DeviceKeychain

    /// Hive's answer, or `HiveRequestError` when it's not a success.
    func send(method: String, path: String, body: Data?, reason: String?, on session: HiveSession) async throws -> Data {
        let request = ConfirmationStatement.Request(method: method, path: path, body: body ?? Data())
        if let reason {
            return try Self.checked(await confirmed(request, reason: reason, on: session))
        }
        let first = try await session.send(method: method, path: path, body: body)
        guard first.status == 428 else { return try Self.checked(first) }
        let reasons = (try? JSONDecoder().decode(ConfirmationRequired.self, from: first.body).reasons) ?? []
        Self.logger.notice("Hive asked to confirm a change")
        return try Self.checked(await confirmed(request, reason: ConfirmationReason.prompt(for: reasons), on: session))
    }

    private func confirmed(
        _ request: ConfirmationStatement.Request,
        reason: String,
        on session: HiveSession
    ) async throws -> (status: Int, body: Data) {
        guard var credential = try keychain.credential(for: hiveID) else { throw ConfirmationWorkflowError.notPaired }
        if credential.confirmationKeyData == nil {
            credential.confirmationKeyData = try ConfirmationKey.make().dataRepresentation
            // Saved before Hive hears of it, so a key Hive has is never one this device lost.
            try keychain.save(credential)
            try await register(credential, on: session)
        }
        let answer = try await sign(request, reason: reason, credential: credential, on: session)
        guard Self.refusal(in: answer) == .noConfirmationKey else { return answer }
        // Saved, but Hive never got it.
        try await register(credential, on: session)
        return try await sign(request, reason: reason, credential: credential, on: session)
    }

    private func sign(
        _ request: ConfirmationStatement.Request,
        reason: String,
        credential: DeviceCredential,
        on session: HiveSession
    ) async throws -> (status: Int, body: Data) {
        guard let keyData = credential.confirmationKeyData else { throw ConfirmationWorkflowError.notPaired }
        let challenge: ConfirmationChallenge = try await session.post(HiveEndpoint.confirmationChallenge)
        let statement = ConfirmationStatement.bytes(hiveID: hiveID, deviceID: credential.deviceID, nonce: challenge.nonce, request: request)
        let signature = try await ConfirmationKey.sign(statement, keyData: keyData, reason: reason)
        let proof = ConfirmationProof(nonce: challenge.nonce, signature: signature)
        // Hive reads a request sent without a body as an empty one.
        let body = request.body.isEmpty ? nil : request.body
        return try await session.send(method: request.method, path: request.path, body: body, confirmation: proof)
    }

    /// Confirmed with the device's sign-in key, so Hive knows the request comes from this device and not
    /// only from its session.
    private func register(_ credential: DeviceCredential, on session: HiveSession) async throws {
        guard let keyData = credential.confirmationKeyData else { throw ConfirmationWorkflowError.notPaired }
        let publicKey = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: keyData).publicKey
        let body = try JSONEncoder().encode(ConfirmationKeyRegistration(publicKey: publicKey.x963Representation))
        let challenge: ConfirmationChallenge = try await session.post(HiveEndpoint.confirmationChallenge)
        let request = ConfirmationStatement.Request(method: "PUT", path: HiveEndpoint.confirmationKey, body: body)
        let statement = ConfirmationStatement.bytes(hiveID: hiveID, deviceID: credential.deviceID, nonce: challenge.nonce, request: request)
        let signature = try credential.signingKey().signature(for: statement).rawRepresentation
        let proof = ConfirmationProof(nonce: challenge.nonce, signature: signature)
        let answer = try await session.send(method: "PUT", path: HiveEndpoint.confirmationKey, body: body, confirmation: proof)
        if Self.refusal(in: answer) == .keyAlreadyRegistered {
            Self.logger.error("Hive has another confirmation key for this device")
            throw ConfirmationWorkflowError.keyMismatch
        }
        _ = try Self.checked(answer)
        Self.logger.notice("Registered this device's confirmation key")
    }

    private static func refusal(in answer: (status: Int, body: Data)) -> ConfirmationRefusalReason? {
        guard answer.status == 403 else { return nil }
        return try? JSONDecoder().decode(ConfirmationRefusal.self, from: answer.body).reason
    }

    private static func checked(_ answer: (status: Int, body: Data)) throws -> Data {
        guard (200 ..< 300).contains(answer.status) else { throw HiveRequestError(status: answer.status, body: answer.body) }
        return answer.body
    }
}

extension ConfirmationWorkflow {
    /// What to tell the person when confirming failed, or nil when the error isn't about confirming.
    static func message(for error: any Error) -> String? {
        switch error {
        case let refused as HiveRequestError where refused.status == 403:
            (try? JSONDecoder().decode(ConfirmationRefusal.self, from: refused.body))?.reason.message
        case ConfirmationKeyError.cancelled:
            "Not confirmed."
        case ConfirmationKeyError.notConfirmed:
            "Touch ID or the password wasn't accepted."
        case ConfirmationKeyError.secureEnclaveUnavailable, ConfirmationKeyError.couldNotSetAccessControl:
            "This device can't make a confirmation key."
        case ConfirmationWorkflowError.keyMismatch:
            "The Hive has another confirmation key for this device. Revoke this device and pair it again."
        default:
            nil
        }
    }
}

extension ConfirmationRefusalReason {
    var message: String {
        switch self {
        case .nonceExpired:
            "That took too long to confirm. Try again."
        case .noConfirmationKey, .keyAlreadyRegistered:
            "The Hive doesn't have this device's confirmation key. Revoke this device and pair it again."
        case .malformed, .nonceNotIssued, .nonceReused, .badSignature:
            "The Hive didn't accept the confirmation. Try again."
        }
    }
}

extension ConfirmationReason {
    /// What Touch ID or the password prompt says, after "Beekeeper is trying to", when Hive asked for a
    /// confirmation Beekeeper didn't expect.
    static func prompt(for reasons: [ConfirmationReason]) -> String {
        let parts = reasons.map(\.prompt)
        return parts.isEmpty ? "confirm a change to the Hive" : parts.formatted(.list(type: .and))
    }

    private var prompt: String {
        switch self {
        case .connectionChanged: "change where Hive connects to a server"
        case .quotaLowered: "lower a server's quota, which removes snapshots"
        case .retentionLowered: "lower what a job keeps, which removes snapshots"
        case .passwordReplaced: "replace a database password"
        case .hostKeyReplaced: "confirm a server's new host key"
        case .sshKeyReplaced: "replace Hive's SSH key for a server"
        case .snapshotsDeleted: "delete snapshots"
        case .identityRegenerated: "give the Hive a new identity"
        }
    }
}
