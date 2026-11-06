import Foundation
import GRDB

/// Opens a database's sealed password in memory, only when its dump is about to run (§7).
struct DatabasePasswordLoader: Sendable {
    let database: HiveDatabase
    let sealer: SecretSealer

    /// Nil when the database has no password stored.
    func password(forDatabase id: UUID) throws -> String? {
        let sealed = try database.writer.read { database in
            try Data.fetchOne(database, sql: "SELECT sealedPassword FROM backupDatabase WHERE id = ?", arguments: [id])
        }
        guard let sealed else { return nil }
        guard let password = String(bytes: try sealer.open(SealedSecret(data: sealed)), encoding: .utf8) else {
            throw DatabasePasswordError.notText
        }
        return password
    }
}

enum DatabasePasswordError: Error {
    /// Passwords are sealed from the text Beekeeper sent, so this means the store is damaged.
    case notText
}
