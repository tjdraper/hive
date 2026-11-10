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
        migrator.registerMigration("Add schedules, the job queue and the job log", migrate: addQueueAndJobLog)
        migrator.registerMigration("Add retention and counting space", migrate: addRetention)
        migrator.registerMigration("Add confirmation keys and snapshot deletions", migrate: addConfirmation)
        // Space counted before files' space set aside past their end was left out stayed in each job's
        // total, so every job is counted whole again at the next pass.
        migrator.registerMigration("Count every job's space again") { database in
            try database.execute(sql: "UPDATE jobSpace SET usedBytes = NULL")
        }
        migrator.registerMigration("Add email settings", migrate: addEmailSettings)

        return migrator
    }

    private static func addEmailSettings(_ database: Database) throws {
        try database.create(table: "emailSettings") { table in
            // One row while email is set up.
            table.primaryKey("singleton", .integer).check { $0 == 1 }
            table.column("host", .text).notNull()
            table.column("port", .integer).notNull()
            table.column("security", .text).notNull()
            table.column("username", .text).notNull()
            table.column("senderAddress", .text).notNull()
            // A JSON array.
            table.column("recipients", .text).notNull()
            table.column("sealedPassword", .blob)
        }
    }

    private static func addConfirmation(_ database: Database) throws {
        try database.alter(table: "device") { table in
            // The X9.63 form of the key the device confirms changes with. Empty until it registers one.
            table.add(column: "confirmationPublicKey", .blob)
        }

        // Kept until the queue gets to them, so a restart in between doesn't forget a deletion that was asked for.
        try database.create(table: "snapshotDeletion") { table in
            table.primaryKey("snapshotID", .blob).references("snapshot", onDelete: .cascade)
            table.column("requestedAt", .datetime).notNull()
        }
    }

    private static func addRetention(_ database: Database) throws {
        try database.alter(table: "snapshot") { table in
            // Whether its files are in its job's `jobSpace.usedBytes`. Every snapshot is, but one being written.
            table.add(column: "isCounted", .boolean).notNull().defaults(to: false)
            // What removing it would free, as last counted. Empty until it's counted, and after a change
            // nearby may have moved it.
            table.add(column: "freesBytes", .integer)
            // Set while it's being removed.
            table.add(column: "removalReason", .text)
        }

        try database.create(table: "jobSpace") { table in
            table.column("driveUUID", .text).notNull()
            // Not a reference to `backupJob`: snapshots outlive their jobs.
            table.column("jobID", .blob).notNull()
            // Each file once, however many of the job's snapshots link to it. Empty until it's counted.
            table.column("usedBytes", .integer)
            table.primaryKey(["driveUUID", "jobID"])
        }

        try database.create(table: "overQuotaServer") { table in
            table.primaryKey("serverID", .blob).references("server", onDelete: .cascade)
            table.column("since", .datetime).notNull()
        }

        try database.alter(table: "hive") { table in
            // Set by a restore: nothing is removed until a device starts retention again (§10, F3).
            table.add(column: "retentionPausedSince", .datetime)
        }

        try addRemovalsToJobLog(database)
    }

    /// SQLite can't make a column optional in place, so the table is made again, keeping every entry
    /// and its ID. The migration runs with foreign keys off, so dropping the old table leaves
    /// `queuedRun.logEntryID` alone.
    private static func addRemovalsToJobLog(_ database: Database) throws {
        try database.create(table: "newJobLogEntry") { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("kind", .text).notNull().defaults(to: "run")
            // Not references to `backupJob` or `server`: entries outlive both.
            table.column("jobID", .blob).notNull()
            table.column("serverID", .blob).notNull()
            table.column("serverName", .text).notNull()
            table.column("jobName", .text).notNull()
            table.column("startedAt", .datetime).notNull()
            table.column("finishedAt", .datetime)
            // Runs only.
            table.column("trigger", .text)
            table.column("failure", .text)
            table.column("pickedUpPartialSnapshot", .boolean)
            table.column("directories", .text)
            table.column("databases", .text)
            // Removals only.
            table.column("removed", .text)
            table.column("notRemoved", .text)
        }
        try database.execute(sql: """
        INSERT INTO newJobLogEntry (
            id, kind, jobID, serverID, serverName, jobName, startedAt, finishedAt,
            "trigger", failure, pickedUpPartialSnapshot, directories, databases
        )
        SELECT
            id, 'run', jobID, serverID, serverName, jobName, startedAt, finishedAt,
            "trigger", failure, pickedUpPartialSnapshot, directories, databases
        FROM jobLogEntry
        """)
        try database.drop(table: "jobLogEntry")
        try database.rename(table: "newJobLogEntry", to: "jobLogEntry")
        try database.create(index: "jobLogEntry_on_jobID", on: "jobLogEntry", columns: ["jobID"])
        try database.create(index: "jobLogEntry_on_serverID", on: "jobLogEntry", columns: ["serverID"])
    }

    private static func addQueueAndJobLog(_ database: Database) throws {
        try database.create(table: "jobSchedule") { table in
            table.primaryKey("jobID", .blob).references("backupJob", onDelete: .cascade)
            // The times and time zone `nextRunAt` was worked out for. A change to either works it out again.
            table.column("scheduleKey", .text).notNull()
            table.column("nextRunAt", .datetime).notNull()
        }

        try database.create(table: "jobLogEntry") { table in
            table.autoIncrementedPrimaryKey("id")
            // Not references to `backupJob` or `server`: entries outlive both.
            table.column("jobID", .blob).notNull().indexed()
            table.column("serverID", .blob).notNull().indexed()
            table.column("serverName", .text).notNull()
            table.column("jobName", .text).notNull()
            table.column("trigger", .text).notNull()
            table.column("startedAt", .datetime).notNull()
            table.column("finishedAt", .datetime)
            table.column("failure", .text)
            table.column("pickedUpPartialSnapshot", .boolean).notNull()
            table.column("directories", .text).notNull()
            table.column("databases", .text).notNull()
        }

        // One row per job, so a job can't wait in the queue twice.
        try database.create(table: "queuedRun") { table in
            table.primaryKey("jobID", .blob).references("backupJob", onDelete: .cascade)
            table.column("trigger", .text).notNull()
            table.column("queuedAt", .datetime).notNull()
            // Set while it runs.
            table.column("logEntryID", .integer).references("jobLogEntry", onDelete: .setNull)
        }
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
