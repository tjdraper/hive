import Foundation
import GRDB
import HiveKit

/// Every change made to the Hive, which device made it and when. Entries are written in the same
/// transaction as the change they record, so neither can be saved without the other.
public struct AuditLog: Sendable {
    static let largestPage = 500

    let database: HiveDatabase

    public init(database: HiveDatabase) {
        self.database = database
    }

    /// The device's name is copied into the entry, so the entry reads the same once the device is revoked.
    static func record(_ event: AuditEvent, by deviceID: UUID, at date: Date, in database: Database) throws {
        guard let device = try PairedDevice.fetchOne(database, key: deviceID) else {
            throw AuditLogError.unknownDevice
        }
        var record = AuditRecord(id: nil, date: date, deviceID: deviceID, deviceName: device.name, event: event)
        try record.insert(database)
    }

    /// Newest first, starting after the entry `before` when given.
    func page(before: Int64?, limit: Int) throws -> AuditLogPage {
        let limit = min(max(limit, 1), Self.largestPage)
        let records = try database.writer.read { database in
            var request = AuditRecord.order(Column("id").desc).limit(limit + 1)
            if let before { request = request.filter(Column("id") < before) }
            return try request.fetchAll(database)
        }
        let entries = records.prefix(limit).compactMap(\.entry)
        return AuditLogPage(entries: entries, nextBefore: records.count > limit ? entries.last?.id : nil)
    }
}

enum AuditLogError: Error, Equatable {
    case unknownDevice
}

struct AuditRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "auditEntry"

    var id: Int64?
    let date: Date
    let deviceID: UUID
    let deviceName: String
    /// Kept as JSON, which GRDB does for a property that isn't a database value.
    let event: AuditEvent

    var entry: AuditEntry? {
        id.map { AuditEntry(id: $0, date: date, deviceID: deviceID, deviceName: deviceName, event: event) }
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
