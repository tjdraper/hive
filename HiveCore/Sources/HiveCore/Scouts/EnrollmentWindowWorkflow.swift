import Foundation
import GRDB
import HiveKit
import os
import ScoutProtocol

enum EnrollmentWindowError: Error, Equatable {
    case refused(EnrollmentWindowProblem)
    /// Hive is restarting, such as for a new identity, and a code now would carry the old key's pin.
    case restarting
}

/// A paired device opening a window for a server's Scout to enroll through, with a code carrying what
/// Scout needs. Opening one is confirmed, since whoever enrolls can send figures for the server.
struct EnrollmentWindowWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Scouts")

    let hiveID: UUID
    let pin: PublicKeyPin
    let settings: HiveSettingsStore
    let database: HiveDatabase
    let windows: EnrollmentWindowStore
    let isRestarting: @Sendable () -> Bool
    let now: @Sendable () -> Date

    /// Throws `ConfirmationError.required`, opening nothing, unless confirmed. Nil when there's no such server.
    func open(forServer serverID: UUID, isConfirmed: Bool, by deviceID: UUID) throws -> EnrollmentWindow? {
        try ConfirmationRequirement.check([.enrollmentWindowOpened], isConfirmed: isConfirmed)
        guard !isRestarting() else { throw EnrollmentWindowError.restarting }
        let addresses = try settings.settings().addresses.options
        guard !addresses.isEmpty else {
            Self.logger.error("Refused to open an enrollment window: no address options")
            throw EnrollmentWindowError.refused(.noAddressOptions)
        }

        let now = now()
        let recorded = try database.writer.write { database in
            guard let serverName = try ScoutStore.serverName(serverID, in: database) else { return false }
            let event = AuditEvent.scout(serverID: serverID, serverName: serverName, change: .enrollmentWindowOpened)
            try AuditLog.record(event, by: deviceID, at: now, in: database)
            return true
        }
        guard recorded else { return nil }

        let (window, token) = windows.open(forServer: serverID, by: deviceID, at: now)
        Self.logger.notice("Opened an enrollment window with \(addresses.count, privacy: .public) address options")
        let code = EnrollmentCode(
            hiveID: hiveID,
            serverID: serverID,
            pin: pin.sha256,
            token: token,
            addresses: addresses.map { EnrollmentCode.Address(host: $0.host, port: $0.port) }
        )
        return EnrollmentWindow(id: window.id, serverID: serverID, code: code.text, expiresInSeconds: Int(EnrollmentWindowStore.lifetime))
    }

    /// Closes the server's open window, recording that only when there was one.
    func close(forServer serverID: UUID, by deviceID: UUID) throws {
        let now = now()
        guard windows.close(forServer: serverID, at: now) else { return }
        try database.writer.write { database in
            guard let serverName = try ScoutStore.serverName(serverID, in: database) else { return }
            let event = AuditEvent.scout(serverID: serverID, serverName: serverName, change: .enrollmentWindowClosed)
            try AuditLog.record(event, by: deviceID, at: now, in: database)
        }
        Self.logger.notice("Closed an enrollment window")
    }
}
