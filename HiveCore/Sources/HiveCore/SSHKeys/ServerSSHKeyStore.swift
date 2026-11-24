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
    /// `ConfirmationError.required` when it would replace one without confirmation, and
    /// `ConfigurationChangeError.refused` for a server without SSH details, which gets its key with
    /// them. Returns nil when no server has that ID.
    func replaceKey(
        forServer id: UUID,
        with key: SealedSSHKey,
        isConfirmed: Bool,
        by deviceID: UUID,
        at date: Date
    ) throws -> SSHKeyReplacement? {
        try database.writer.write { database in
            guard var record = try ServerRecord.fetchOne(database, key: id) else { return nil }
            guard record.connection != nil else {
                throw ConfigurationChangeError.refused([ConfigurationProblem(field: .connection, reason: .missing)])
            }
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

extension ServerSSHKeyStore {
    /// Gives the server its rotated key, with an audit entry, only while its key and connection are
    /// still those the rotation started with. False when either changed meanwhile.
    func rotateKey(forServer id: UUID, from old: SSHTarget, to key: SealedSSHKey, by deviceID: UUID, at date: Date) throws -> Bool {
        try database.writer.write { database in
            guard var record = try ServerRecord.fetchOne(database, key: id),
                  record.sshPublicKey == old.key.publicKey.line, record.connection == old.connection
            else { return false }
            record.sealedSSHKey = key.sealedSeed.data
            record.sshPublicKey = key.publicKey.line
            try record.update(database)
            let change = ServerChange.sshKeyRotated(old: old.key.publicKey.fingerprint, new: key.publicKey.fingerprint)
            try AuditLog.record(.server(serverID: id, serverName: record.name, change: change), by: deviceID, at: date, in: database)
            return true
        }
    }
}

struct SSHKeyReplacement {
    let old: OpenSSHPublicKey?
    let new: OpenSSHPublicKey
}
