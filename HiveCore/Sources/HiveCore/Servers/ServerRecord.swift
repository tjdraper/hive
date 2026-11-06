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
    /// The host key a device confirmed.
    var hostKey: String?
    let createdAt: Date

    init(id: UUID, draft: ServerDraft, createdAt: Date) {
        self.id = id
        name = draft.name
        host = draft.connection.host
        port = draft.connection.port
        user = draft.connection.user
        quotaBytes = draft.quotaBytes
        hostKey = nil
        self.createdAt = createdAt
    }

    var connection: ServerConnection {
        ServerConnection(host: host, port: port, user: user)
    }

    var server: Server {
        Server(id: id, name: name, connection: connection, quotaBytes: quotaBytes, hasConfirmedHostKey: hostKey != nil)
    }

    mutating func apply(_ draft: ServerDraft) {
        name = draft.name
        host = draft.connection.host
        port = draft.connection.port
        user = draft.connection.user
        quotaBytes = draft.quotaBytes
    }
}
