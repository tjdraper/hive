import Foundation
import GRDB

public enum DeviceStoreError: Error, Equatable {
    case alreadyPaired
}

public struct DeviceStore: Sendable {
    let database: HiveDatabase

    public init(database: HiveDatabase) {
        self.database = database
    }

    func add(name: String, publicKey: Data, at date: Date) throws -> PairedDevice {
        let device = PairedDevice(id: UUID(), name: name, publicKey: publicKey, pairedAt: date, lastSeenAt: nil)
        do {
            try database.writer.write { try device.insert($0) }
        } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
            throw DeviceStoreError.alreadyPaired
        }
        return device
    }

    func device(id: UUID) throws -> PairedDevice? {
        try database.writer.read { try PairedDevice.fetchOne($0, key: id) }
    }

    func recordSignIn(id: UUID, at date: Date) throws {
        try database.writer.write { database in
            try database.execute(sql: "UPDATE device SET lastSeenAt = ? WHERE id = ?", arguments: [date, id])
        }
    }

    /// Its key can't sign in again. Sessions it already has are ended separately, by `SessionStore`.
    func remove(id: UUID) throws {
        _ = try database.writer.write { try PairedDevice.deleteOne($0, key: id) }
    }
}
