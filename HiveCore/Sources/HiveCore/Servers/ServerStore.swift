import Foundation
import GRDB
import HiveKit

/// Servers in Hive's store. Each change is saved with its audit entries, all or none of them.
struct ServerStore: Sendable {
    let database: HiveDatabase

    /// In name order.
    func all() throws -> [Server] {
        try database.writer.read { database in
            try ServerRecord.fetchAll(database)
                .map(\.server)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func server(id: UUID) throws -> Server? {
        try database.writer.read { try ServerRecord.fetchOne($0, key: id)?.server }
    }

    /// `draft` has passed `ServerDraftCheck`.
    func add(_ draft: ServerDraft, sshKey: SealedSSHKey, by deviceID: UUID, at date: Date) throws -> Server {
        try database.writer.write { database in
            try Self.checkNameIsFree(draft.name, except: nil, in: database)
            let record = ServerRecord(id: UUID(), draft: draft, sshKey: sshKey, createdAt: date)
            try record.insert(database)
            let event = AuditEvent.server(serverID: record.id, serverName: record.name, change: .added(connection: record.connection))
            try AuditLog.record(event, by: deviceID, at: date, in: database)
            return record.server
        }
    }

    /// Changing where Hive connects clears the server's host key and its jobs' database passwords, so
    /// they have to be confirmed and entered again before anything is sent there. Hive's SSH key stays,
    /// since only its public half is ever sent. Returns nil when no
    /// server has that ID.
    func change(id: UUID, to draft: ServerDraft, by deviceID: UUID, at date: Date) throws -> (old: Server, new: Server)? {
        try database.writer.write { database in
            guard var record = try ServerRecord.fetchOne(database, key: id) else { return nil }
            let old = record.server
            try Self.checkNameIsFree(draft.name, except: id, in: database)

            record.apply(draft)
            if record.connection != old.connection {
                record.hostKey = nil
                try database.execute(
                    sql: """
                    UPDATE backupDatabase SET sealedPassword = NULL
                    WHERE jobID IN (SELECT id FROM backupJob WHERE serverID = ?)
                    """,
                    arguments: [id]
                )
            }
            try record.update(database)

            for change in Self.changes(from: old, to: record.server) {
                try AuditLog.record(.server(serverID: id, serverName: record.name, change: change), by: deviceID, at: date, in: database)
            }
            return (old, record.server)
        }
    }

    /// Removes the server and its jobs from the configuration, recording each. Their snapshots stay on
    /// the backup drive. Returns the server removed, or nil when no server has that ID.
    func remove(id: UUID, by deviceID: UUID, at date: Date) throws -> Server? {
        try database.writer.write { database in
            guard let record = try ServerRecord.fetchOne(database, key: id) else { return nil }
            let jobs = try Row.fetchAll(database, sql: "SELECT id, name FROM backupJob WHERE serverID = ?", arguments: [id])
            for job in jobs {
                let event = AuditEvent.backupJob(jobID: job["id"], serverName: record.name, jobName: job["name"], change: .removed)
                try AuditLog.record(event, by: deviceID, at: date, in: database)
            }
            try AuditLog.record(.server(serverID: id, serverName: record.name, change: .removed), by: deviceID, at: date, in: database)
            try record.delete(database)
            return record.server
        }
    }

    static func changes(from old: Server, to new: Server) -> [ServerChange] {
        var changes: [ServerChange] = []
        if old.name != new.name { changes.append(.renamed(old: old.name, new: new.name)) }
        if old.connection != new.connection { changes.append(.connection(old: old.connection, new: new.connection)) }
        if old.quotaBytes != new.quotaBytes { changes.append(.quota(old: old.quotaBytes, new: new.quotaBytes)) }
        return changes
    }

    /// Two servers with the same name couldn't be told apart in Beekeeper.
    private static func checkNameIsFree(_ name: String, except id: UUID?, in database: Database) throws {
        let taken = try ServerRecord.fetchAll(database).contains {
            $0.id != id && $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }
        if taken { throw ConfigurationChangeError.refused([ConfigurationProblem(field: .name, reason: .duplicate)]) }
    }
}
