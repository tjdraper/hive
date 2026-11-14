import CryptoKit
import Foundation
import GRDB
import HiveKit

/// Puts what a recovery file holds back into the store, each value where `RecoveryContentsReader` read
/// it from. Secrets go in as they're given, already sealed for this Mac's storage key.
enum RecoveryContentsWriter {
    /// A Hive with none of these has nothing a restore could overwrite. Its devices and logs stay.
    static func isUnconfigured(in database: Database) throws -> Bool {
        let row = try Row.fetchOne(database, sql: """
        SELECT
            (SELECT COUNT(*) FROM server) AS servers,
            (SELECT COUNT(*) FROM emailSettings) AS email,
            (SELECT COUNT(*) FROM snapshot) AS snapshots,
            recoveryPublicKey, backupDriveUUID
        FROM hive
        """)
        guard let row else { return false }
        let counts: [Int] = [row["servers"], row["email"], row["snapshots"]]
        let recoveryKey: Data? = row["recoveryPublicKey"]
        let drive: String? = row["backupDriveUUID"]
        return counts.allSatisfy { $0 == 0 } && recoveryKey == nil && drive == nil
    }

    /// Takes the Hive's ID, name and settings, its recovery key's public half, and every server, job and
    /// email setting. Retention waits from `date` until a device starts it again (§10).
    static func write(
        _ sealed: RecoveryContents,
        recoveryKey: Curve25519.KeyAgreement.PublicKey,
        at date: Date,
        in database: Database
    ) throws {
        let hive = sealed.hive
        // Read back before it's stored, since every settings read would fail on options it can't read.
        let addressOptions = hive.addressOptions
            .flatMap { try? HiveSettingsStore.addressOptions(from: $0) }
            .flatMap { try? HiveSettingsStore.stored($0) }
        try database.execute(
            sql: """
            UPDATE hive SET
                id = ?, createdAt = ?, name = ?, networkAccess = ?, listenAddress = ?, port = ?, addressOptions = ?,
                advertisesOnLocalNetwork = ?, sendsBuildExpiryWarnings = ?,
                backupDriveUUID = ?, backupDriveName = ?,
                recoveryPublicKey = ?, recoveryKeySavedAt = ?, recoveryFileWrittenAt = NULL, recoveryFileDigest = NULL,
                retentionPausedSince = ?
            """,
            arguments: [
                hive.id, hive.createdAt, hive.name, hive.networkAccess, hive.listenAddress, hive.port, addressOptions ?? "[]",
                hive.advertisesOnLocalNetwork ?? true, hive.sendsBuildExpiryWarnings ?? true,
                hive.backupDrive?.volumeUUID, hive.backupDrive?.name,
                recoveryKey.rawRepresentation, date,
                date,
            ]
        )
        for server in sealed.servers {
            try write(server, in: database)
        }
        if let email = sealed.email {
            try write(email, in: database)
        }
    }

    private static func write(_ server: RecoveryContents.Server, in database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO server (id, name, host, port, user, quotaBytes, createdAt, hostKey, sealedSSHKey, sshPublicKey, snapshotFolder)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                server.id, server.name, server.host, server.port, server.user, server.quotaBytes, server.createdAt,
                server.hostKey, server.sshKey?.seed, server.sshKey?.publicKey, server.snapshotFolder,
            ]
        )
        for job in server.jobs {
            try write(job, onServer: server.id, in: database)
        }
    }

    private static func write(_ job: RecoveryContents.Job, onServer serverID: UUID, in database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO backupJob (id, serverID, name, dailySnapshots, monthlySnapshots, createdAt, snapshotFolder)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [job.id, serverID, job.name, job.dailySnapshots, job.monthlySnapshots, job.createdAt, job.snapshotFolder]
        )
        for (position, directory) in job.directories.enumerated() {
            try database.execute(
                sql: "INSERT INTO backupDirectory (jobID, position, path, folder) VALUES (?, ?, ?, ?)",
                arguments: [job.id, position, directory.path, directory.folder]
            )
        }
        for (position, dump) in job.databases.enumerated() {
            try database.execute(
                sql: """
                INSERT INTO backupDatabase (id, jobID, position, kind, serviceName, user, name, sealedPassword)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [dump.id, job.id, position, dump.kind, dump.serviceName, dump.user, dump.name, dump.password]
            )
        }
        for minute in job.minutesOfDay {
            try database.execute(sql: "INSERT INTO backupTime (jobID, minuteOfDay) VALUES (?, ?)", arguments: [job.id, minute])
        }
    }

    private static func write(_ email: RecoveryContents.Email, in database: Database) throws {
        let settings = EmailSettings(
            host: email.host,
            port: email.port,
            security: .implicitTLS,
            username: email.username,
            senderAddress: email.senderAddress,
            recipients: email.recipients
        )
        var record = EmailSettingsRecord(settings, sealedPassword: email.password)
        // As it was stored, rather than through `EmailSecurity`, so nothing is changed on the way back.
        record.security = email.security
        try record.insert(database)
    }
}
