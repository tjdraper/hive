import Foundation
import HiveKit
import Observation
import os

enum HiveLinkError: Error {
    case notPaired
}

/// One Hive's connection: whether Beekeeper can reach it and sign in, and what it last said about itself.
/// Signing in again when a session runs out or Hive restarts is `HiveSession`'s, so it never asks.
@Observable
final class HiveLink {
    enum Status: Equatable {
        case connecting
        /// The Hive took a new identity and is restarting, and Beekeeper on its Mac is pairing again.
        case pairingAgain
        case connected
        case offline
        /// Hive showed a key other than the pinned one. Beekeeper never accepts it without pairing again.
        case identityChanged
        /// Hive turned the sign-in down: this device was revoked, or the Hive was reset.
        case notRecognized
        /// This device has no key for the Hive, such as after revoking itself.
        case notPaired
        case lockedOut
        case needsUpdate(OutdatedApp)
        case failed(String)
    }

    private static let logger = Logger(subsystem: BeekeeperLog.subsystem, category: "Connection")

    let hiveID: UUID
    private(set) var status = Status.connecting
    private(set) var overview: HiveOverview?
    /// The ID this Hive gave this device, so its own row in the device list can be marked.
    private(set) var deviceID: UUID?
    private var session: HiveSession?
    private let keychain: DeviceKeychain

    init(hive: KnownHive, keychain: DeviceKeychain) {
        hiveID = hive.id
        self.keychain = keychain
        connect(to: hive.addresses.first)
    }

    /// Starts over with a new session, such as after pairing again or when the port changed.
    func connect(to address: HiveAddress?) {
        session = nil
        deviceID = nil
        do {
            guard let address, let credential = try keychain.credential(for: hiveID) else {
                status = .notPaired
                return
            }
            session = HiveSession(
                connection: HiveConnection(address: address, pin: credential.pin),
                hiveID: hiveID,
                deviceID: credential.deviceID,
                key: try credential.signingKey()
            )
            deviceID = credential.deviceID
            status = .connecting
        } catch {
            Self.logger.error("Couldn't read this device's key for a Hive: \(String(describing: error), privacy: .public)")
            status = .failed("Beekeeper couldn't read its key for this Hive.")
        }
    }

    /// Fetches the overview, which also finds out whether the Hive can be reached and signed in to.
    func refresh() async {
        guard session != nil else { return }
        overview = try? await perform { try await $0.get(HiveEndpoint.overview) }
    }

    /// Runs a request on the signed-in session, and updates the status when the problem is reaching
    /// or signing in to the Hive rather than the request itself.
    func perform<Value>(_ request: (HiveSession) async throws -> Value) async throws -> Value {
        guard let session else { throw HiveLinkError.notPaired }
        do {
            let value = try await request(session)
            if status != .connected { status = .connected }
            return value
        } catch {
            if let problem = Self.status(for: error) {
                if problem != status {
                    Self.logger.notice("A Hive's connection changed: \(String(describing: problem), privacy: .public)")
                }
                status = problem
            }
            throw error
        }
    }

    /// A request whose change may need confirming, decoded. With a `reason` it asks for Touch ID or the
    /// password first, saying that; without one it asks only if Hive says the change needs it.
    func confirmed<Value: Decodable>(
        _ method: String,
        _ path: String,
        body: (some Encodable)? = String?.none,
        reason: String?,
        as _: Value.Type = Value.self
    ) async throws -> Value {
        let data = try await confirmed(method, path, body: body, reason: reason)
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw HiveConnectionError.unreadableResponse
        }
    }

    /// For a request whose answer has no body.
    @discardableResult
    func confirmed(_ method: String, _ path: String, body: (some Encodable)? = String?.none, reason: String?) async throws -> Data {
        let encoded = try body.map { try JSONEncoder().encode($0) }
        let workflow = ConfirmationWorkflow(hiveID: hiveID, keychain: keychain)
        return try await perform { try await workflow.send(method: method, path: path, body: encoded, reason: reason, on: $0) }
    }

    /// The Hive's live updates, until it ends them, such as when the session runs out.
    func liveUpdates() async throws -> AsyncThrowingStream<LiveUpdate, any Error> {
        try await perform { try await $0.liveUpdates() }
    }

    /// While Beekeeper on the Hive's Mac pairs again after a new identity. Pairing again connects it.
    func startPairingAgain() {
        session = nil
        deviceID = nil
        status = .pairingAgain
    }

    /// After this device revokes itself, or the Hive took a new identity: its key is no use any more.
    func forgetCredential() {
        try? keychain.delete(hiveID: hiveID)
        session = nil
        deviceID = nil
        overview = nil
        status = .notPaired
    }

    private static func status(for error: any Error) -> Status? {
        switch error {
        case HiveConnectionError.wrongKey: .identityChanged
        case HiveConnectionError.signInRefused: .notRecognized
        case HiveConnectionError.lockedOut: .lockedOut
        case HiveConnectionError.incompatible(let outdated): .needsUpdate(outdated)
        // A request whose task was cancelled, such as by a view reloading, says nothing about the Hive.
        case let error as URLError where error.code == .cancelled: nil
        case is URLError: .offline
        case is HiveRequestError, is CancellationError, is ConfirmationKeyError, is ConfirmationWorkflowError: nil
        default: .failed(error.localizedDescription)
        }
    }

    /// What to tell the person when a request fails.
    static func message(for error: any Error) -> String {
        if let message = ConfirmationWorkflow.message(for: error) { return message }
        return switch error {
        case let refused as HiveRequestError:
            "The Hive turned the request down (\(refused.status))."
        case HiveConnectionError.wrongKey:
            "The Hive didn't show the key it paired with."
        case HiveConnectionError.signInRefused:
            "The Hive turned down the sign-in. This device may have been revoked."
        case HiveConnectionError.lockedOut:
            "Too many failed sign-ins. Try again in 15 minutes."
        case HiveConnectionError.incompatible(update: .hive):
            "Update Hive to work with this Beekeeper."
        case HiveConnectionError.incompatible(update: .beekeeper):
            "Update Beekeeper to work with this Hive."
        case HiveLinkError.notPaired:
            "This device isn't paired with the Hive."
        case is URLError:
            "Couldn't reach the Hive."
        default:
            error.localizedDescription
        }
    }
}
