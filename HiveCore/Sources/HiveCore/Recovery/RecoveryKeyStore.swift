import CryptoKit
import Foundation
import GRDB
import HiveKit

enum RecoveryKeySaving: Equatable {
    case saved(replacedAnother: Bool)
    /// The Hive had this key already.
    case unchanged
}

/// The recovery key's public half and the recovery file last written with it, kept in the one `hive` row.
struct RecoveryKeyStore: Sendable {
    let database: HiveDatabase

    func state() throws -> RecoveryKeyState {
        try database.writer.read { database in
            let row = try Row.fetchOne(database, sql: """
            SELECT recoveryKeySavedAt, recoveryPublicKey, recoveryFileWrittenAt, recoveryFileDigest FROM hive
            """)
            return RecoveryKeyState(
                keySavedAt: row?["recoveryKeySavedAt"],
                publicKey: row?["recoveryPublicKey"],
                fileWrittenAt: row?["recoveryFileWrittenAt"],
                fileDigest: row?["recoveryFileDigest"]
            )
        }
    }

    static func publicKey(in database: Database) throws -> Curve25519.KeyAgreement.PublicKey? {
        try Data.fetchOne(database, sql: "SELECT recoveryPublicKey FROM hive")
            .flatMap { try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: $0) }
    }

    /// Saves the key with its audit entry. The recovery file written with the old key no longer counts
    /// as written.
    func save(_ key: Curve25519.KeyAgreement.PublicKey, by deviceID: UUID, at date: Date) throws -> RecoveryKeySaving {
        try database.writer.write { database in
            let old = try Self.publicKey(in: database)
            guard old?.rawRepresentation != key.rawRepresentation else { return .unchanged }
            try database.execute(
                sql: """
                UPDATE hive SET recoveryPublicKey = ?, recoveryKeySavedAt = ?, recoveryFileWrittenAt = NULL, recoveryFileDigest = NULL
                """,
                arguments: [key.rawRepresentation, date]
            )
            try AuditLog.record(.recoveryKeySaved(replacedAnother: old != nil), by: deviceID, at: date, in: database)
            return .saved(replacedAnother: old != nil)
        }
    }

    /// Only while `key` is still the Hive's, so a file written just as the key was replaced never
    /// counts for the new one.
    func recordFileWritten(at date: Date, digest: Data, with key: Curve25519.KeyAgreement.PublicKey) throws {
        try database.writer.write { database in
            try database.execute(
                sql: "UPDATE hive SET recoveryFileWrittenAt = ?, recoveryFileDigest = ? WHERE recoveryPublicKey = ?",
                arguments: [date, digest, key.rawRepresentation]
            )
        }
    }
}
