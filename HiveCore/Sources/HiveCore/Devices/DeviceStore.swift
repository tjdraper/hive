import Foundation
import GRDB
import HiveKit

public enum DeviceStoreError: Error, Equatable {
    case alreadyPaired
}

public struct DeviceStore: Sendable {
    let database: HiveDatabase

    public init(database: HiveDatabase) {
        self.database = database
    }

    /// Records the device with `event` in the audit log, made by the new device itself.
    func add(name: String, publicKey: Data, at date: Date, auditedAs event: AuditEvent) throws -> PairedDevice {
        let device = PairedDevice(id: UUID(), name: name, publicKey: publicKey, pairedAt: date, lastSeenAt: nil)
        do {
            try database.writer.write { database in
                try device.insert(database)
                try AuditLog.record(event, by: device.id, at: date, in: database)
            }
        } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
            throw DeviceStoreError.alreadyPaired
        }
        return device
    }

    func device(id: UUID) throws -> PairedDevice? {
        try database.writer.read { try PairedDevice.fetchOne($0, key: id) }
    }

    /// Oldest first.
    func all() throws -> [PairedDevice] {
        try database.writer.read { try PairedDevice.order(Column("pairedAt"), Column("name")).fetchAll($0) }
    }

    func recordSignIn(id: UUID, at date: Date) throws {
        try database.writer.write { database in
            try database.execute(sql: "UPDATE device SET lastSeenAt = ? WHERE id = ?", arguments: [date, id])
        }
    }

    /// Its key can't sign in again. Sessions it already has are ended separately, by `SessionStore`.
    /// Returns the device removed, or nil when there was none with that ID.
    func remove(id: UUID, by revokingDeviceID: UUID, at date: Date) throws -> PairedDevice? {
        try database.writer.write { database in
            guard let device = try PairedDevice.fetchOne(database, key: id) else { return nil }
            // Recorded first, since revoking itself, the revoking device has to still be there to be named.
            try AuditLog.record(.deviceRevoked(deviceID: device.id, deviceName: device.name), by: revokingDeviceID, at: date, in: database)
            try device.delete(database)
            return device
        }
    }
}
