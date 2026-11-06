import Foundation
import HiveKit

/// Tells whether a dump worked, from how it exited, what it wrote to standard error, and the start and
/// end of the dump itself. The messages can name the database and its user, so they're only matched
/// here, never logged.
enum DumpResultReader {
    /// What a shell exits with when it can't find a command, and what Hive's MySQL script exits with
    /// when it finds neither tool.
    static let toolMissingStatus: Int32 = 127

    /// mysqldump and mariadb-dump end every complete dump with this comment.
    static let mysqlCompletionLine = "-- Dump completed"
    /// The first bytes of every pg_dump custom format archive.
    static let postgresMagic = Data("PGDMP".utf8)

    private static let containerGoneMessages = ["No such container", "is not running"]
    private static let loginMessages = [
        "(using password: YES)",
        "password authentication failed",
        "no password supplied",
    ]
    private static let mysqlUnknownDatabaseMessage = "Unknown database"
    /// Postgres says `database "<name>" does not exist`, and `role "<name>" does not exist` for an
    /// unknown user, which it refuses before looking at the password.
    private static let postgresMissingMessage = "does not exist"
    private static let notPermittedMessages = ["Access denied", "insufficient privileges", "permission denied"]
    private static let unreachableMessages = ["Can't connect to", "could not connect to", "Connection refused"]

    static func failure(of result: ChildProcess.Result, kind: DatabaseKind, dump: DumpFileSummary) -> BackupFailure? {
        guard result.status == 0 else { return failure(of: result) }
        guard dump.bytesDumped > 0 else { return .databaseDumpEmpty }
        switch kind {
        case .mysql:
            let ending = String(bytes: dump.ending, encoding: .utf8) ?? ""
            return ending.contains(mysqlCompletionLine) ? nil : .databaseDumpIncomplete
        case .postgres:
            return dump.beginning.starts(with: postgresMagic) ? nil : .databaseDumpIncomplete
        }
    }

    /// For a dump, or the container list, that exited with an error.
    static func failure(of result: ChildProcess.Result) -> BackupFailure {
        if result.status == SSHFailureReader.sshErrorStatus, let connection = SSHFailureReader.failure(in: result) {
            return BackupFailure(connection)
        }
        if result.status == toolMissingStatus { return .databaseDumpToolMissing }
        let output = String(bytes: result.standardError, encoding: .utf8) ?? ""
        let doesNotExist = output.contains(postgresMissingMessage)
        if containsAny(containerGoneMessages, in: output) { return .databaseContainerNotFound }
        if containsAny(loginMessages, in: output) || (doesNotExist && output.contains("role \"")) { return .databaseLoginRefused }
        if output.contains(mysqlUnknownDatabaseMessage) || (doesNotExist && output.contains("database \"")) { return .databaseMissing }
        if containsAny(notPermittedMessages, in: output) { return .databaseNotPermitted }
        if containsAny(unreachableMessages, in: output) { return .databaseUnreachable }
        return .databaseDumpFailed
    }

    private static func containsAny(_ messages: [String], in output: String) -> Bool {
        messages.contains { output.contains($0) }
    }
}
