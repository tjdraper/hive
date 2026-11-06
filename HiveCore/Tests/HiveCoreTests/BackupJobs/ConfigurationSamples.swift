import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird

enum ConfigurationSamples {
    static let password = "correct horse battery staple"

    static let server = ServerDraft(
        name: "Studio Web",
        connection: ServerConnection(host: "web.example.com", user: "backup"),
        quotaBytes: 500_000_000_000
    )

    static let database = DatabaseSettings(kind: .mysql, location: .container(serviceName: "site_db"), user: "site", name: "site")

    static func job(name: String = "Main site", password: String? = password) -> BackupJobDraft {
        BackupJobDraft(
            name: name,
            directories: [
                BackupDirectory(path: "/var/www/site/uploads", folder: "uploads"),
                BackupDirectory(path: "/var/lib/docker/volumes/galleries/_data", folder: "images/galleries"),
            ],
            databases: [BackupDatabaseDraft(id: nil, settings: database, password: password)],
            times: [TimeOfDay(hour: 14, minute: 0), TimeOfDay(hour: 2, minute: 30)],
            retention: RetentionTiers(dailySnapshots: 14, monthlySnapshots: 12)
        )
    }
}

extension APIFixture {
    func addServer(_ draft: ServerDraft = ConfigurationSamples.server) async throws -> Server {
        let answer = try await send(.post, HiveEndpoint.servers, json: draft)
        guard answer.status == .created else { throw APIFixtureError.unexpectedStatus(answer.status) }
        return try answer.decoded(as: Server.self)
    }

    func addJob(_ draft: BackupJobDraft = ConfigurationSamples.job(), to server: Server) async throws -> BackupJob {
        let answer = try await send(.post, HiveEndpoint.jobs(onServer: server.id), json: draft)
        guard answer.status == .created else { throw APIFixtureError.unexpectedStatus(answer.status) }
        return try answer.decoded(as: BackupJob.self)
    }

    /// Stands in for a device confirming the server's host key, which has no route yet.
    func confirmHostKey(of server: Server) throws {
        try signIn.database.writer.write { database in
            try database.execute(sql: "UPDATE server SET hostKey = 'ssh-ed25519 AAAA' WHERE id = ?", arguments: [server.id])
        }
    }

    var servers: ServerStore {
        ServerStore(database: signIn.database)
    }

    var jobs: BackupJobStore {
        BackupJobStore(database: signIn.database)
    }
}
