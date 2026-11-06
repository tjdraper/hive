import Darwin
import Foundation
import GRDB

struct SnapshotFolders: Equatable {
    let server: String
    let job: String
}

enum SnapshotFolderResolverError: Error, Equatable {
    case noFreeName
}

/// Names a server's and a job's folders on the drive the first time either is backed up, and keeps
/// those names for good, so renaming either in Beekeeper never moves its snapshots (§9).
struct SnapshotFolderResolver: Sendable {
    let database: HiveDatabase

    func folders(serverID: UUID, serverName: String, jobID: UUID, jobName: String, in hiveFolder: URL) throws -> SnapshotFolders {
        try database.writer.write { database in
            let server = try Self.serverFolder(serverID, name: serverName, in: hiveFolder, database: database)
            let job = try Self.jobFolder(jobID, name: jobName, under: server, in: hiveFolder, database: database)
            return SnapshotFolders(server: server, job: job)
        }
    }

    private static func serverFolder(_ id: UUID, name: String, in hiveFolder: URL, database: Database) throws -> String {
        let known = try String.fetchOne(database, sql: "SELECT snapshotFolder FROM server WHERE id = ?", arguments: [id])
            ?? String.fetchOne(database, sql: "SELECT serverFolder FROM snapshot WHERE serverID = ? LIMIT 1", arguments: [id])
        let configured = try String.fetchAll(
            database,
            sql: "SELECT snapshotFolder FROM server WHERE snapshotFolder IS NOT NULL AND id != ?",
            arguments: [id]
        )
        let cataloged = try String.fetchAll(database, sql: "SELECT serverFolder FROM snapshot WHERE serverID != ?", arguments: [id])
        let folder = try known ?? freeName(
            from: SnapshotFolderName.candidates(name: name, id: id),
            taken: Set(configured + cataloged),
            in: hiveFolder
        )
        try database.execute(sql: "UPDATE server SET snapshotFolder = ? WHERE id = ?", arguments: [folder, id])
        return folder
    }

    private static func jobFolder(
        _ id: UUID,
        name: String,
        under serverFolder: String,
        in hiveFolder: URL,
        database: Database
    ) throws -> String {
        let known = try String.fetchOne(database, sql: "SELECT snapshotFolder FROM backupJob WHERE id = ?", arguments: [id])
            ?? String.fetchOne(database, sql: "SELECT jobFolder FROM snapshot WHERE jobID = ? LIMIT 1", arguments: [id])
        let configured = try String.fetchAll(
            database,
            sql: """
            SELECT snapshotFolder FROM backupJob
            WHERE snapshotFolder IS NOT NULL AND id != ? AND serverID IN (SELECT id FROM server WHERE snapshotFolder = ?)
            """,
            arguments: [id, serverFolder]
        )
        let cataloged = try String.fetchAll(
            database,
            sql: "SELECT jobFolder FROM snapshot WHERE serverFolder = ? AND jobID != ?",
            arguments: [serverFolder, id]
        )
        let folder = try known ?? freeName(
            from: SnapshotFolderName.candidates(name: name, id: id),
            taken: Set(configured + cataloged),
            in: hiveFolder.appending(path: serverFolder, directoryHint: .isDirectory)
        )
        try database.execute(sql: "UPDATE backupJob SET snapshotFolder = ? WHERE id = ?", arguments: [folder, id])
        return folder
    }

    /// The first candidate that nothing in the store uses, and that isn't already on the drive, such as
    /// a folder left from a store restored from an older backup.
    private static func freeName(from candidates: [String], taken: Set<String>, in parent: URL) throws -> String {
        for candidate in candidates where !taken.contains(candidate) {
            var info = stat()
            let path = parent.appending(path: candidate, directoryHint: .isDirectory).fileSystemPath
            if lstat(path, &info) != 0, errno == ENOENT { return candidate }
        }
        throw SnapshotFolderResolverError.noFreeName
    }
}
