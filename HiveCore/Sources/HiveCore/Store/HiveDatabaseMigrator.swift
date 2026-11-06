import Foundation
import GRDB

/// Every change to the store's shape, in order. A migration that has shipped is never edited, since
/// stores that already ran it won't run it again.
enum HiveDatabaseMigrator {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("Create the Hive and its devices") { database in
            try database.create(table: "hive") { table in
                // One row, ever.
                table.primaryKey("singleton", .integer).check { $0 == 1 }
                table.column("id", .blob).notNull()
                table.column("createdAt", .datetime).notNull()
            }
            try database.execute(
                sql: "INSERT INTO hive (singleton, id, createdAt) VALUES (1, ?, ?)",
                arguments: [UUID(), Date()]
            )

            try database.create(table: "device") { table in
                table.primaryKey("id", .blob)
                table.column("name", .text).notNull()
                table.column("publicKey", .blob).notNull().unique()
                table.column("pairedAt", .datetime).notNull()
                table.column("lastSeenAt", .datetime)
            }
        }

        return migrator
    }
}
