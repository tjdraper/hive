import Foundation
import GRDB

/// Every change to the store's shape, in order. A migration that has shipped is never edited, since
/// stores that already ran it won't run it again.
enum HiveDatabaseMigrator {
    /// `defaultHiveName` names a Hive whose store is created or migrated by this run.
    static func migrator(defaultHiveName: String) -> DatabaseMigrator {
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

        migrator.registerMigration("Add the Hive's settings and the audit log") { database in
            try database.alter(table: "hive") { table in
                table.add(column: "name", .text).notNull().defaults(to: defaultHiveName)
                table.add(column: "networkAccess", .text).notNull().defaults(to: StoredNetworkAccess.thisMacOnly.rawValue)
                table.add(column: "listenAddress", .text)
                // Empty until it's changed, which means the default for how the daemon runs.
                table.add(column: "port", .integer)
            }

            try database.create(table: "auditEntry") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("date", .datetime).notNull()
                // Not a reference to `device`, since entries outlive the devices that made them.
                table.column("deviceID", .blob).notNull()
                table.column("deviceName", .text).notNull()
                table.column("event", .text).notNull()
            }
        }

        return migrator
    }
}
