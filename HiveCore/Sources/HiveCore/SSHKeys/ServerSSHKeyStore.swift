import Foundation
import GRDB
import HiveKit

/// Hive's SSH key for each server, kept in the server's row.
struct ServerSSHKeyStore: Sendable {
    let database: HiveDatabase

    /// Nil when no server has that ID, or the server has no key yet.
    func publicKey(forServer id: UUID) throws -> OpenSSHPublicKey? {
        try database.writer.read { try ServerRecord.fetchOne($0, key: id) }?.sshPublicKey.flatMap(OpenSSHPublicKey.init(line:))
    }

    /// Replaces the server's key, or gives it its first, with an audit entry. Throws
    /// `ConfirmationError.required` when it would replace one without confirmation. Returns nil when no
    /// server has that ID.
    func replaceKey(
        forServer id: UUID,
        with key: SealedSSHKey,
        isConfirmed: Bool,
        by deviceID: UUID,
        at date: Date
    ) throws -> SSHKeyReplacement? {
        try database.writer.write { database in
            guard var record = try ServerRecord.fetchOne(database, key: id) else { return nil }
            let old = record.sshPublicKey.flatMap(OpenSSHPublicKey.init(line:))
            try ConfirmationRequirement.check(ConfirmationRequirement.reasons(replacingSSHKey: old), isConfirmed: isConfirmed)
            record.sealedSSHKey = key.sealedSeed.data
            record.sshPublicKey = key.publicKey.line
            try record.update(database)
            let change = ServerChange.newSSHKey(old: old?.fingerprint, new: key.publicKey.fingerprint)
            try AuditLog.record(.server(serverID: id, serverName: record.name, change: change), by: deviceID, at: date, in: database)
            return SSHKeyReplacement(old: old, new: key.publicKey)
        }
    }
}

struct SSHKeyReplacement {
    let old: OpenSSHPublicKey?
    let new: OpenSSHPublicKey
}
