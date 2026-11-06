import Foundation
import GRDB
import HiveKit

/// The chosen backup drive, kept in the one `hive` row by its volume UUID.
struct BackupDriveStore: Sendable {
    let database: HiveDatabase

    func chosen() throws -> BackupDriveIdentity? {
        try database.writer.read(Self.chosen(in:))
    }

    /// Saves the choice with its audit entry, both or neither. Choosing the same drive again changes nothing.
    func choose(_ drive: BackupDriveIdentity, by deviceID: UUID, at date: Date) throws {
        try database.writer.write { database in
            let old = try Self.chosen(in: database)
            guard old != drive else { return }
            try database.execute(
                sql: "UPDATE hive SET backupDriveUUID = ?, backupDriveName = ?",
                arguments: [drive.volumeUUID.uuidString, drive.name]
            )
            try AuditLog.record(.backupDriveChosen(old: old, new: drive), by: deviceID, at: date, in: database)
        }
    }

    private static func chosen(in database: Database) throws -> BackupDriveIdentity? {
        guard let row = try Row.fetchOne(database, sql: "SELECT backupDriveUUID, backupDriveName FROM hive"),
              let uuid = (row["backupDriveUUID"] as String?).flatMap(UUID.init(uuidString:))
        else { return nil }
        return BackupDriveIdentity(volumeUUID: uuid, name: row["backupDriveName"] ?? "")
    }
}
