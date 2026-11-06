import Foundation
import GRDB
import HiveKit

struct ServerRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "server"

    let id: UUID
    var name: String
    var host: String
    var port: Int
    var user: String
    var quotaBytes: Int64?
    /// The host key a device confirmed, as `OpenSSHPublicKey.line` writes it.
    var hostKey: String?
    let createdAt: Date
    /// The seed of Hive's SSH key for the server, sealed (§7).
    var sealedSSHKey: Data?
    /// As `OpenSSHPublicKey.line` writes it.
    var sshPublicKey: String?

    init(id: UUID, draft: ServerDraft, sshKey: SealedSSHKey, createdAt: Date) {
        self.id = id
        name = draft.name
        host = draft.connection.host
        port = draft.connection.port
        user = draft.connection.user
        quotaBytes = draft.quotaBytes
        hostKey = nil
        self.createdAt = createdAt
        sealedSSHKey = sshKey.sealedSeed.data
        sshPublicKey = sshKey.publicKey.line
    }

    var connection: ServerConnection {
        ServerConnection(host: host, port: port, user: user)
    }

    var server: Server {
        Server(
            id: id,
            name: name,
            connection: connection,
            quotaBytes: quotaBytes,
            confirmedHostKey: hostKey.flatMap(OpenSSHPublicKey.init(line:))?.hostKeyFingerprint,
            sshKeyFingerprint: sshPublicKey.flatMap(OpenSSHPublicKey.init(line:))?.fingerprint
        )
    }

    mutating func apply(_ draft: ServerDraft) {
        name = draft.name
        host = draft.connection.host
        port = draft.connection.port
        user = draft.connection.user
        quotaBytes = draft.quotaBytes
    }
}
