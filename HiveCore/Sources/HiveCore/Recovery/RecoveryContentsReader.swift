import Foundation
import GRDB

/// Reads the configuration a recovery file holds out of the store, in one transaction so it's all from
/// the same moment. Secrets come out as they're stored, sealed for this Mac's storage key.
enum RecoveryContentsReader {
    static func sealedContents(writtenAt: Date, in database: Database) throws -> RecoveryContents {
        RecoveryContents(
            format: RecoveryContents.currentFormat,
            writtenAt: writtenAt,
            hive: try hive(in: database),
            servers: try servers(in: database),
            email: try email(in: database)
        )
    }

    private static func hive(in database: Database) throws -> RecoveryContents.Hive {
        let sql = """
        SELECT id, createdAt, name, networkAccess, listenAddress, port, addressOptions, advertisesOnLocalNetwork,
            sendsBuildExpiryWarnings, backupDriveUUID, backupDriveName
        FROM hive
        """
        guard let row = try Row.fetchOne(database, sql: sql) else { throw HiveDatabaseError.missingHiveID }
        let driveUUID: String? = row["backupDriveUUID"]
        return RecoveryContents.Hive(
            id: row["id"],
            createdAt: row["createdAt"],
            name: row["name"],
            networkAccess: row["networkAccess"],
            listenAddress: row["listenAddress"],
            port: row["port"],
            addressOptions: row["addressOptions"],
            advertisesOnLocalNetwork: row["advertisesOnLocalNetwork"],
            sendsBuildExpiryWarnings: row["sendsBuildExpiryWarnings"],
            backupDrive: driveUUID.map { RecoveryContents.BackupDrive(volumeUUID: $0, name: row["backupDriveName"] ?? "") }
        )
    }

    private static func servers(in database: Database) throws -> [RecoveryContents.Server] {
        let jobs = Dictionary(grouping: try self.jobs(in: database), by: \.serverID)
        let rows = try Row.fetchAll(database, sql: """
        SELECT id, name, host, port, user, quotaBytes, createdAt, hostKey, sealedSSHKey, sshPublicKey, snapshotFolder
        FROM server ORDER BY createdAt, id
        """)
        return rows.map { row in
            let id: UUID = row["id"]
            let seed: Data? = row["sealedSSHKey"]
            let publicKey: String? = row["sshPublicKey"]
            return RecoveryContents.Server(
                id: id,
                name: row["name"],
                host: row["host"],
                port: row["port"],
                user: row["user"],
                quotaBytes: row["quotaBytes"],
                createdAt: row["createdAt"],
                hostKey: row["hostKey"],
                sshKey: seed.flatMap { seed in publicKey.map { RecoveryContents.SSHKey(seed: seed, publicKey: $0) } },
                snapshotFolder: row["snapshotFolder"],
                jobs: jobs[id, default: []].map(\.job)
            )
        }
    }

    private static func jobs(in database: Database) throws -> [(serverID: UUID, job: RecoveryContents.Job)] {
        let directories = Dictionary(
            grouping: try Row.fetchAll(database, sql: "SELECT jobID, path, folder FROM backupDirectory ORDER BY jobID, position"),
            by: { $0["jobID"] as UUID }
        )
        let databases = Dictionary(
            grouping: try Row.fetchAll(database, sql: """
            SELECT id, jobID, kind, serviceName, user, name, sealedPassword FROM backupDatabase ORDER BY jobID, position
            """),
            by: { $0["jobID"] as UUID }
        )
        let times = Dictionary(
            grouping: try Row.fetchAll(database, sql: "SELECT jobID, minuteOfDay FROM backupTime ORDER BY jobID, minuteOfDay"),
            by: { $0["jobID"] as UUID }
        )

        let rows = try Row.fetchAll(database, sql: """
        SELECT id, serverID, name, dailySnapshots, monthlySnapshots, createdAt, snapshotFolder
        FROM backupJob ORDER BY createdAt, id
        """)
        return rows.map { row in
            let id: UUID = row["id"]
            let job = RecoveryContents.Job(
                id: id,
                name: row["name"],
                dailySnapshots: row["dailySnapshots"],
                monthlySnapshots: row["monthlySnapshots"],
                createdAt: row["createdAt"],
                snapshotFolder: row["snapshotFolder"],
                directories: directories[id, default: []].map { RecoveryContents.Directory(path: $0["path"], folder: $0["folder"]) },
                databases: databases[id, default: []].map { row in
                    RecoveryContents.Database(
                        id: row["id"],
                        kind: row["kind"],
                        serviceName: row["serviceName"],
                        user: row["user"],
                        name: row["name"],
                        password: row["sealedPassword"]
                    )
                },
                minutesOfDay: times[id, default: []].map { $0["minuteOfDay"] }
            )
            return (row["serverID"], job)
        }
    }

    private static func email(in database: Database) throws -> RecoveryContents.Email? {
        guard let record = try EmailSettingsRecord.fetchOne(database) else { return nil }
        return RecoveryContents.Email(
            host: record.host,
            port: record.port,
            security: record.security,
            username: record.username,
            senderAddress: record.senderAddress,
            recipients: record.recipients,
            password: record.sealedPassword
        )
    }
}
