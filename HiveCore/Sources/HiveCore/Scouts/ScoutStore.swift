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
                let event = AuditEvent.scout(serverID: serverID, serverName: serverName, change: .enrolled(replacedAnother: replaced))
                try AuditLog.record(event, by: deviceID, at: date, in: database)
                return (scout, replaced)
            }
        } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
            throw ScoutStoreError.keyInUse
        }
    }

    /// Only what changed is written, so a Scout signing in again with nothing new costs nothing more.
    func recordSignIn(id: UUID, version: String?, platform: String?, at date: Date) throws {
        try database.writer.write { database in
            guard var scout = try ScoutRecord.fetchOne(database, key: id) else { return }
            scout.lastSeenAt = date
            scout.version = version
            scout.platform = platform
            try scout.update(database)
        }
    }

    /// Its key can't sign in again. Its sessions are ended separately, by `SessionStore`. Returns false
    /// when the server has no Scout.
    func remove(forServer serverID: UUID, by deviceID: UUID, at date: Date) throws -> Bool {
        try database.writer.write { database in
            guard let scout = try ScoutRecord.filter(Column("serverID") == serverID).fetchOne(database),
                  let serverName = try Self.serverName(serverID, in: database)
            else { return false }
            let event = AuditEvent.scout(serverID: serverID, serverName: serverName, change: .removed)
            try AuditLog.record(event, by: deviceID, at: date, in: database)
            try scout.delete(database)
            return true
        }
    }

    static func serverName(_ serverID: UUID, in database: Database) throws -> String? {
        try String.fetchOne(database, sql: "SELECT name FROM server WHERE id = ?", arguments: [serverID])
    }
}
