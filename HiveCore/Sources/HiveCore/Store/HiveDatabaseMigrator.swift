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

        migrator.registerMigration("Add servers and backup jobs", migrate: addServersAndJobs)

        migrator.registerMigration("Add Hive's SSH key for each server") { database in
            try database.alter(table: "server") { table in
                table.add(column: "sealedSSHKey", .blob)
                table.add(column: "sshPublicKey", .text)
            }
        }

        migrator.registerMigration("Add the backup drive and the snapshot catalog", migrate: addBackupDriveAndSnapshots)

        return migrator
    }

    private static func addBackupDriveAndSnapshots(_ database: Database) throws {
        try database.alter(table: "hive") { table in
            table.add(column: "backupDriveUUID", .text)
            table.add(column: "backupDriveName", .text)
        }

        // Each is named the first time it's backed up, and never renamed (§9).
        try database.alter(table: "server") { table in
            table.add(column: "snapshotFolder", .text)
        }
        try database.alter(table: "backupJob") { table in
            table.add(column: "snapshotFolder", .text)
        }

        try database.create(table: "snapshot") { table in
            table.primaryKey("id", .blob)
            // Not references to `backupJob` or `server`: removing either removes its configuration,
            // and its snapshots stay on the drive (§10).
            table.column("jobID", .blob).notNull().indexed()
            table.column("serverID", .blob).notNull()
            table.column("driveUUID", .text).notNull()
            table.column("serverFolder", .text).notNull()
            table.column("jobFolder", .text).notNull()
            table.column("folder", .text).notNull()
            table.column("state", .text).notNull()
            table.column("startedAt", .datetime).notNull()
            table.column("completedAt", .datetime)
            table.uniqueKey(["driveUUID", "serverFolder", "jobFolder", "folder"])
        }
    }

    private static func addServersAndJobs(_ database: Database) throws {
        try database.create(table: "server") { table in
            table.primaryKey("id", .blob)
            table.column("name", .text).notNull()
            table.column("host", .text).notNull()
            table.column("port", .integer).notNull()
            table.column("user", .text).notNull()
            table.column("quotaBytes", .integer)
            table.column("hostKey", .text)
            table.column("createdAt", .datetime).notNull()
        }

        try database.create(table: "backupJob") { table in
            table.primaryKey("id", .blob)
            table.column("serverID", .blob).notNull().indexed().references("server", onDelete: .cascade)
            table.column("name", .text).notNull()
            table.column("dailySnapshots", .integer).notNull()
            table.column("monthlySnapshots", .integer).notNull()
            table.column("createdAt", .datetime).notNull()
        }

        try database.create(table: "backupDirectory") { table in
            table.column("jobID", .blob).notNull().references("backupJob", onDelete: .cascade)
            table.column("position", .integer).notNull()
            table.column("path", .text).notNull()
            table.column("folder", .text).notNull()
            table.primaryKey(["jobID", "position"])
        }

        try database.create(table: "backupDatabase") { table in
            table.primaryKey("id", .blob)
            table.column("jobID", .blob).notNull().indexed().references("backupJob", onDelete: .cascade)
            table.column("position", .integer).notNull()
            table.column("kind", .text).notNull()
            // Empty for a database running on the server itself.
            table.column("serviceName", .text)
            table.column("user", .text).notNull()
            table.column("name", .text).notNull()
            table.column("sealedPassword", .blob)
        }

        try database.create(table: "backupTime") { table in
            table.column("jobID", .blob).notNull().references("backupJob", onDelete: .cascade)
            table.column("minuteOfDay", .integer).notNull()
            table.primaryKey(["jobID", "minuteOfDay"])
        }
    }
}
