import Foundation
import GRDB
import HiveKit

enum HostKeyRecording {
    case noServer
    /// The server's host, port or user changed after the scan.
    case connectionChanged
    case recorded(old: OpenSSHPublicKey?, server: Server)
}

/// The host key a device confirmed for each server, kept in the server's row.
struct HostKeyStore: Sendable {
    let database: HiveDatabase

    /// Records the key `scan` found with an audit entry, as long as the server still connects where it
    /// was scanned. Throws `ConfirmationError.required` when it would replace another key without confirmation.
    func record(
        _ scan: PendingHostKeyScans.Scan,
        forServer id: UUID,
        isConfirmed: Bool,
        by deviceID: UUID,
        at date: Date
    ) throws -> HostKeyRecording {
        let key = scan.key
        return try database.writer.write { database in
            guard var record = try ServerRecord.fetchOne(database, key: id) else { return .noServer }
            guard record.connection == scan.connection else { return .connectionChanged }
            let old = record.hostKey.flatMap(OpenSSHPublicKey.init(line:))
            try ConfirmationRequirement.check(ConfirmationRequirement.reasons(replacingHostKey: old, with: key), isConfirmed: isConfirmed)
            if old != key {
                record.hostKey = key.line
                try record.update(database)
                let change = ServerChange.hostKeyConfirmed(old: old?.hostKeyFingerprint, new: key.hostKeyFingerprint)
                try AuditLog.record(.server(serverID: id, serverName: record.name, change: change), by: deviceID, at: date, in: database)
            }
            return .recorded(old: old, server: record.server)
        }
    }
}
