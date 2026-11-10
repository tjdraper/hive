import Foundation
import GRDB
import HiveKit

enum ConfirmationKeyRegistrationOutcome: Equatable {
    case registered
    /// The device had registered this same key already.
    case unchanged
    /// The device has a different key. Only pairing again replaces it, so a stolen session can't swap in its own.
    case refused
    case noDevice
}

/// Each device's confirmation key, kept in its row, so revoking the device revokes the key with it.
struct ConfirmationKeyStore: Sendable {
    let database: HiveDatabase

    /// The X9.63 form, or nil when the device has none or doesn't exist.
    func key(ofDevice id: UUID) throws -> Data? {
        try database.writer.read { database in
            try Data.fetchOne(database, sql: "SELECT confirmationPublicKey FROM device WHERE id = ?", arguments: [id])
        }
    }

    /// `key` is a valid P-256 key's X9.63 form. Recorded in the audit log when it's registered.
    func register(_ key: Data, forDevice id: UUID, at date: Date) throws -> ConfirmationKeyRegistrationOutcome {
        try database.writer.write { database in
            guard let row = try Row.fetchOne(database, sql: "SELECT confirmationPublicKey FROM device WHERE id = ?", arguments: [id]) else {
                return .noDevice
            }
            if let existing: Data = row["confirmationPublicKey"] { return existing == key ? .unchanged : .refused }
            try database.execute(sql: "UPDATE device SET confirmationPublicKey = ? WHERE id = ?", arguments: [key, id])
            try AuditLog.record(.confirmationKeyRegistered, by: id, at: date, in: database)
            return .registered
        }
    }
}
