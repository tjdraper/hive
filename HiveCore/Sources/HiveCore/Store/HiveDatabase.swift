import Foundation
import GRDB
import os

/// Hive's store: its configuration, and later the job queue, the snapshot catalog and the logs. It
/// lives in the data directory, so the Mac's own backup picks it up.
public struct HiveDatabase: Sendable {
    static let fileName = "hive.sqlite"

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Store")

    let writer: any DatabaseWriter

    private init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try HiveDatabaseMigrator.migrator.migrate(writer)
    }

    public static func open(in directory: URL) throws -> HiveDatabase {
        let path = directory.appending(path: fileName, directoryHint: .notDirectory).fileSystemPath
        let database = try HiveDatabase(writer: DatabasePool(path: path))
        logger.notice("Opened the store")
        return database
    }

    static func inMemory() throws -> HiveDatabase {
        try HiveDatabase(writer: DatabaseQueue())
    }

    /// Created once, with the store, and kept when Hive is restored on a new Mac.
    public func hiveID() throws -> UUID {
        try writer.read { database in
            guard let id = try UUID.fetchOne(database, sql: "SELECT id FROM hive") else {
                throw HiveDatabaseError.missingHiveID
            }
            return id
        }
    }
}

public enum HiveDatabaseError: Error, Equatable {
    case missingHiveID
}
