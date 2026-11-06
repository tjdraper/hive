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

    /// Records `key` with an audit entry, as long as the server still connects where it was scanned.
    func record(
        _ key: OpenSSHPublicKey,
        forServer id: UUID,
        scannedOn connection: ServerConnection,
        by deviceID: UUID,
        at date: Date
    ) throws -> HostKeyRecording {
        try database.writer.write { database in
            guard var record = try ServerRecord.fetchOne(database, key: id) else { return .noServer }
            guard record.connection == connection else { return .connectionChanged }
            let old = record.hostKey.flatMap(OpenSSHPublicKey.init(line:))
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
