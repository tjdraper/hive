import Foundation
import GRDB
import os

/// Servers' figures, in a database apart from Hive's store (§6): its writes every few seconds don't
/// contend with the store's, and losing it loses history, never configuration.
public struct MetricsDatabase: Sendable {
    static let folderName = "Metrics"
    static let fileName = "metrics.sqlite"

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Metrics")

    let writer: any DatabaseWriter

    private init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try MetricsDatabaseMigrator.migrator.migrate(writer)
    }

    /// Opens `Metrics/metrics.sqlite` in the data directory, leaving the folder out of Time Machine.
    /// One that can't be opened, such as after a downgrade, is set aside and a new one started, since
    /// Hive's backups matter more than its metrics history.
    public static func open(in dataDirectory: URL) throws -> MetricsDatabase {
        let folder = dataDirectory.appending(path: folderName, directoryHint: .isDirectory)
        do {
            return try open(folder: folder)
        } catch {
            logger.fault("Couldn't open the metrics database, starting a new one: \(String(describing: error), privacy: .public)")
            let asideName = "\(folderName) (unreadable \(Int(Date().timeIntervalSince1970)))"
            let aside = dataDirectory.appending(path: asideName, directoryHint: .isDirectory)
            try FileManager.default.moveItem(at: folder, to: aside)
            return try open(folder: folder)
        }
    }

    private static func open(folder: URL) throws -> MetricsDatabase {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try excludeFromBackup(folder)
        let path = folder.appending(path: fileName, directoryHint: .notDirectory).fileSystemPath
        let database = try MetricsDatabase(writer: DatabasePool(path: path))
        logger.notice("Opened the metrics database")
        return database
    }

    /// Time Machine copies a changed file whole, and these change every 10 seconds (§6). Set on the
    /// folder, so the write-ahead log is left out too.
    static func excludeFromBackup(_ folder: URL) throws {
        var folder = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }

    static func inMemory() throws -> MetricsDatabase {
        try MetricsDatabase(writer: DatabaseQueue())
    }
}
