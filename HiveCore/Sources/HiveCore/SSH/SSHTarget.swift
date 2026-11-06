import Foundation
import GRDB
import HiveKit

/// A server Hive can connect to: it has a key of Hive's and a host key a device confirmed.
struct SSHTarget: Sendable {
    let serverID: UUID
    let connection: ServerConnection
    let hostKey: OpenSSHPublicKey
    let key: SSHKeyPair

    /// The name the server's host key is filed under in `known_hosts`, so the key stays the server's own
    /// whatever its host is called, and two servers on one host never share an entry.
    var hostKeyAlias: String {
        serverID.uuidString.lowercased()
    }
}

enum SSHTargetLookup: Sendable {
    case ready(SSHTarget)
    case unavailable(ConnectionFailure)
}

/// Reads what Hive needs to connect to a server, opening its key only now, in memory.
struct SSHTargetLoader: Sendable {
    let database: HiveDatabase
    let sealer: SecretSealer

    /// Nil when no server has that ID.
    func target(forServer id: UUID) throws -> SSHTargetLookup? {
        guard let record = try database.writer.read({ try ServerRecord.fetchOne($0, key: id) }) else { return nil }
        guard let sealedKey = record.sealedSSHKey else { return .unavailable(.noSSHKey) }
        guard let hostKey = record.hostKey.flatMap(OpenSSHPublicKey.init(line:)) else { return .unavailable(.noConfirmedHostKey) }
        let key = try SSHKeyPair(seed: sealer.open(SealedSecret(data: sealedKey)))
        return .ready(SSHTarget(serverID: id, connection: record.connection, hostKey: hostKey, key: key))
    }
}
