import Foundation
import GRDB
import os

/// Hive's store: its configuration, the job queue, the snapshot catalog and the logs. It lives in the
/// data directory, so the Mac's own backup picks it up.
public struct HiveDatabase: Sendable {
    static let fileName = "hive.sqlite"

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Store")

    let writer: any DatabaseWriter

    private init(writer: any DatabaseWriter, defaultHiveName: String) throws {
        self.writer = writer
        try HiveDatabaseMigrator.migrator(defaultHiveName: defaultHiveName).migrate(writer)
    }

    /// `defaultHiveName` names the Hive when the store is first created or first gains a name.
    public static func open(in directory: URL, defaultHiveName: String) throws -> HiveDatabase {
        let path = directory.appending(path: fileName, directoryHint: .notDirectory).fileSystemPath
        let name = DisplayName.validated(defaultHiveName) ?? "Hive"
        let database = try HiveDatabase(writer: DatabasePool(path: path), defaultHiveName: name)
        logger.notice("Opened the store")
        return database
    }

    static func inMemory(defaultHiveName: String = "Test Hive") throws -> HiveDatabase {
        try HiveDatabase(writer: DatabaseQueue(), defaultHiveName: defaultHiveName)
    }

    /// Runs the store's migrations up to and including the one named, for tests of later migrations.
    static func inMemory(migratedUpTo lastMigration: String) throws -> any DatabaseWriter {
        let writer = try DatabaseQueue()
        try HiveDatabaseMigrator.migrator(defaultHiveName: "Test Hive").migrate(writer, upTo: lastMigration)
        return writer
    }

    static func migrate(_ writer: any DatabaseWriter, defaultHiveName: String) throws -> HiveDatabase {
        try HiveDatabase(writer: writer, defaultHiveName: defaultHiveName)
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
