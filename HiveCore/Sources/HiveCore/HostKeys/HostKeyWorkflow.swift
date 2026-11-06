import Foundation
import HiveKit
import os

enum HostKeyConfirmationOutcome {
    case confirmed(Server)
    case refused(HostKeyConfirmationRefusalReason)
}

/// Scanning a server's host key, and recording it once a device confirms the fingerprint (§11).
struct HostKeyWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "HostKeys")

    let store: HostKeyStore
    let servers: ServerStore
    let scanner: any HostKeyScanning
    let pending: PendingHostKeyScans
    let now: @Sendable () -> Date

    /// Nil when no server has that ID. Records nothing.
    func scan(serverID: UUID) async throws -> HostKeyScanResult? {
        guard let server = try servers.server(id: serverID) else { return nil }
        let started = ContinuousClock.now
        let outcome = try await scanner.scan(server.connection)
        let seconds = (ContinuousClock.now - started).roundedSeconds
        switch outcome {
        case .found(let key):
            pending.record(key, forServer: serverID, connection: server.connection, at: now())
            let comparison = switch server.confirmedHostKey {
            case nil: "none confirmed"
            case key.hostKeyFingerprint: "the confirmed key"
            default: "not the confirmed key"
            }
            Self.logger.notice(
                "Scanned a host key: \(key.keyType, privacy: .public), \(comparison, privacy: .public), in \(seconds, privacy: .public)s"
            )
            return .found(key: key.hostKeyFingerprint)
        case .failed(let reason):
            Self.logger.notice("Couldn't scan a host key: \(reason.rawValue, privacy: .public), after \(seconds, privacy: .public)s")
            return .failed(reason: reason)
        }
    }

    /// Nil when no server has that ID.
    func confirm(serverID: UUID, fingerprint: String, by deviceID: UUID) throws -> HostKeyConfirmationOutcome? {
        guard let scan = pending.scan(forServer: serverID, at: now()) else {
            return try servers.server(id: serverID) == nil ? nil : .refused(.noScan)
        }
        guard scan.key.fingerprint == fingerprint else {
            Self.logger.notice("Refused a host key confirmation: the fingerprint isn't the scanned one")
            return .refused(.fingerprintMismatch)
        }

        switch try store.record(scan.key, forServer: serverID, scannedOn: scan.connection, by: deviceID, at: now()) {
        case .noServer:
            pending.remove(forServer: serverID)
            return nil
        case .connectionChanged:
            pending.remove(forServer: serverID)
            Self.logger.notice("Refused a host key confirmation: the server's connection changed after the scan")
            return .refused(.noScan)
        case .recorded(let old, let server):
            pending.remove(forServer: serverID)
            let reasons = ConfirmationRequirement.reasons(replacingHostKey: old, with: scan.key)
            let logged = ConfirmationRequirement.logged(reasons)
            let keyType = scan.key.keyType
            Self.logger.notice("Recorded a confirmed host key: \(keyType, privacy: .public) (to confirm: \(logged, privacy: .public))")
            return .confirmed(server)
        }
    }
}
