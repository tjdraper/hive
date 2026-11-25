import Foundation
import GRDB
import HiveKit

/// A server's Scout: the key it signs in with, and what it last reported about itself.
struct ScoutRecord: Codable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "scout"

    let id: UUID
    let serverID: UUID
    /// The X9.63 form of the P-256 key the Scout made when it enrolled.
    let publicKey: Data
    let enrolledAt: Date
    var lastSeenAt: Date?
    /// Scout's own version, as it reported it when it last signed in.
    var version: String?
    /// The system and CPU it was built for, such as `linux-x86_64`.
    var platform: String?
    /// The protocol version it last signed in with, accepted or not.
    var protocolVersion: Int?
    /// When the server last started, on its clock, as `FigureAlertCheck` last noted it.
    var bootedAt: Int64?
}

enum ScoutStoreError: Error, Equatable {
    /// The server was removed after its window was opened.
    case noServer
    /// Another Scout already enrolled with the same key.
    case keyInUse
}

/// Scouts in Hive's store, at most one for each server. Each change is saved with its audit entry.
struct ScoutStore: Sendable {
    let database: HiveDatabase

    func scout(id: UUID) throws -> ScoutRecord? {
        try database.writer.read { try ScoutRecord.fetchOne($0, key: id) }
    }

    func scout(forServer serverID: UUID) throws -> ScoutRecord? {
        try database.writer.read { try ScoutRecord.filter(Column("serverID") == serverID).fetchOne($0) }
    }

    /// Records the server's Scout, replacing the last one, as enrolled through a window `openedBy` opened.
    func enroll(
        serverID: UUID,
        publicKey: Data,
        at date: Date,
        openedBy deviceID: UUID
    ) throws -> (scout: ScoutRecord, replacedAnother: Bool) {
        let scout = ScoutRecord(id: UUID(), serverID: serverID, publicKey: publicKey, enrolledAt: date)
        do {
            return try database.writer.write { database in
                guard let serverName = try Self.serverName(serverID, in: database) else { throw ScoutStoreError.noServer }
                let replaced = try ScoutRecord.filter(Column("serverID") == serverID).deleteAll(database) > 0
                try scout.insert(database)
                try database.execute(sql: "UPDATE server SET hasMetrics = 1 WHERE id = ?", arguments: [serverID])
                let event = AuditEvent.scout(serverID: serverID, serverName: serverName, change: .enrolled(replacedAnother: replaced))
                try AuditLog.record(event, by: deviceID, at: date, in: database)
                return (scout, replaced)
            }
        } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
            throw ScoutStoreError.keyInUse
        }
    }

    /// Only what changed is written, so a Scout signing in again with nothing new costs nothing more.
    func recordSignIn(id: UUID, version: String?, platform: String?, protocolVersion: Int, at date: Date) throws {
        try database.writer.write { database in
            guard var scout = try ScoutRecord.fetchOne(database, key: id) else { return }
            scout.lastSeenAt = date
            scout.version = version
            scout.platform = platform
            scout.protocolVersion = protocolVersion
            try scout.update(database)
        }
    }

    /// The server no longer has metrics: its Scout's key can't sign in again, and a restored server
    /// stops waiting for its Scout to enroll. Its Scout's sessions are ended separately, by
    /// `SessionStore`. Returns false when the server has no metrics.
    func removeMetrics(forServer serverID: UUID, by deviceID: UUID, at date: Date) throws -> Bool {
        try database.writer.write { database in
            guard let server = try Row.fetchOne(database, sql: "SELECT name, hasMetrics FROM server WHERE id = ?", arguments: [serverID])
            else { return false }
            let removedScout = try ScoutRecord.filter(Column("serverID") == serverID).deleteAll(database) > 0
            guard removedScout || server["hasMetrics"] else { return false }
            try database.execute(sql: "UPDATE server SET hasMetrics = 0 WHERE id = ?", arguments: [serverID])
            let event = AuditEvent.scout(serverID: serverID, serverName: server["name"], change: .removed)
            try AuditLog.record(event, by: deviceID, at: date, in: database)
            return true
        }
    }

    /// Whether the server has metrics, with or without a Scout enrolled. Nil when there's no such server.
    func hasMetrics(_ serverID: UUID) throws -> Bool? {
        try database.writer.read { try Bool.fetchOne($0, sql: "SELECT hasMetrics FROM server WHERE id = ?", arguments: [serverID]) }
    }

    /// Every server with metrics, by name, with its Scout while one is enrolled.
    func serversWithMetrics() throws -> [(serverID: UUID, scout: ScoutRecord?)] {
        try database.writer.read { database in
            let serverIDs = try UUID.fetchAll(database, sql: "SELECT id FROM server WHERE hasMetrics = 1 ORDER BY name")
            let scouts = try ScoutRecord.fetchAll(database)
            return serverIDs.map { id in (id, scouts.first { $0.serverID == id }) }
        }
    }

    static func serverName(_ serverID: UUID, in database: Database) throws -> String? {
        try String.fetchOne(database, sql: "SELECT name FROM server WHERE id = ?", arguments: [serverID])
    }
}
