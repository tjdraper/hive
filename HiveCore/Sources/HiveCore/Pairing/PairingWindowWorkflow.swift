import Foundation
import GRDB
import HiveKit
import os

enum PairingWindowError: Error, Equatable {
    case refused(PairingWindowProblem)
    /// Hive is restarting, such as for a new identity, and a code now would carry the old key's pin.
    case restarting
}

/// A paired device opening a window for another to pair through, with a code carrying what the new
/// device needs. Opening one is confirmed, since whoever pairs gets full access.
struct PairingWindowWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Pairing")

    let hiveID: UUID
    let pin: PublicKeyPin
    let settings: HiveSettingsStore
    let database: HiveDatabase
    let windows: PairingWindowStore
    let isRestarting: @Sendable () -> Bool
    let now: @Sendable () -> Date

    /// Throws `ConfirmationError.required`, opening nothing, unless confirmed.
    func open(isConfirmed: Bool, by deviceID: UUID) throws -> PairingWindow {
        try ConfirmationRequirement.check([.pairingWindowOpened], isConfirmed: isConfirmed)
        guard !isRestarting() else { throw PairingWindowError.restarting }
        let addresses = try settings.settings().addresses.options
        guard !addresses.isEmpty else {
            Self.logger.error("Refused to open a pairing window: no address options")
            throw PairingWindowError.refused(.noAddressOptions)
        }

        let now = now()
        let openerName = try database.writer.write { database in
            try AuditLog.record(.pairingWindowOpened, by: deviceID, at: now, in: database)
            return try PairedDevice.fetchOne(database, key: deviceID)?.name ?? ""
        }
        let (window, token) = windows.open(by: deviceID, named: openerName, at: now)
        Self.logger.notice("Opened a pairing window with \(addresses.count, privacy: .public) address options")
        let code = PairingCode(hiveID: hiveID, pin: pin, token: token, addresses: addresses)
        return PairingWindow(id: window.id, code: code.text, expiresInSeconds: Int(PairingWindowStore.lifetime))
    }

    /// Closes the open window, recording that only when there was one.
    func close(by deviceID: UUID) throws {
        let now = now()
        guard windows.close(at: now) else { return }
        try database.writer.write { database in
            try AuditLog.record(.pairingWindowClosed, by: deviceID, at: now, in: database)
        }
        Self.logger.notice("Closed the pairing window")
    }

    func state() -> PairingWindowState {
        windows.state(at: now())
    }
}
