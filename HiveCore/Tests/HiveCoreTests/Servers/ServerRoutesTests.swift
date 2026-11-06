import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct ServerRoutesTests {
    private let fixture: APIFixture

    init() throws {
        fixture = try APIFixture()
    }

    private static func draft(
        name: String = "Web",
        host: String = "web",
        port: Int = 22,
        user: String = "root",
        quotaBytes: Int64? = nil
    ) -> ServerDraft {
        ServerDraft(name: name, connection: ServerConnection(host: host, port: port, user: user), quotaBytes: quotaBytes)
    }

    @Test("A server is added, then listed and read back as saved, trimmed and with its host in lowercase")
    func addsServer() async throws {
        // Arrange
        var draft = ConfigurationSamples.server
        draft.name = " Studio Web "
        draft.connection.host = " Web.Example.COM"

        // Act
        let added = try await fixture.addServer(draft)

        // Assert
        let expected = Server(
            id: added.id,
            name: "Studio Web",
            connection: ServerConnection(host: "web.example.com", port: 22, user: "backup"),
            quotaBytes: 500_000_000_000,
            confirmedHostKey: nil,
            sshKeyFingerprint: added.sshKeyFingerprint
        )
        #expect(added == expected)
        #expect(added.sshKeyFingerprint?.hasPrefix("SHA256:") == true)
        #expect(try await fixture.send(.get, HiveEndpoint.server(added.id)).decoded(as: Server.self) == expected)
        #expect(try await fixture.send(.get, HiveEndpoint.servers).decoded(as: [Server].self) == [expected])
        #expect(try fixture.auditEvents().first == .server(
            serverID: added.id,
            serverName: "Studio Web",
            change: .added(connection: expected.connection)
        ))
    }

    @Test("Servers are listed in name order")
    func listsInNameOrder() async throws {
        // Arrange
        for name in ["Web 10", "mail", "Web 9"] {
            var draft = ConfigurationSamples.server
            draft.name = name
            _ = try await fixture.addServer(draft)
        }

        // Act
        let servers = try await fixture.send(.get, HiveEndpoint.servers).decoded(as: [Server].self)

        // Assert
        #expect(servers.map(\.name) == ["mail", "Web 9", "Web 10"])
    }

    @Test("Changing a server's name, connection and quota saves each, recorded by the device that did it")
    func changesServer() async throws {
        // Arrange
        let server = try await fixture.addServer()
        let draft = ServerDraft(
            name: "Studio Web 2",
            connection: ServerConnection(host: "web2.example.com", port: 2222, user: "hive"),
            quotaBytes: nil
        )

        // Act
        let answer = try await fixture.send(.put, HiveEndpoint.server(server.id), json: draft)

        // Assert
        #expect(answer.status == .ok)
        let changed = try answer.decoded(as: Server.self)
        #expect(changed.draft == draft)
        #expect(try fixture.servers.server(id: server.id) == changed)
        let entries = try fixture.auditLog.page(before: nil, limit: 3).entries
        #expect(entries.map(\.event) == [
            .server(serverID: server.id, serverName: "Studio Web 2", change: .quota(old: 500_000_000_000, new: nil)),
            .server(serverID: server.id, serverName: "Studio Web 2", change: .connection(old: server.connection, new: draft.connection)),
            .server(serverID: server.id, serverName: "Studio Web 2", change: .renamed(old: "Studio Web", new: "Studio Web 2")),
        ])
        #expect(entries.allSatisfy { $0.deviceID == fixture.signIn.device.id })
    }

    @Test("Sending a server unchanged records nothing")
    func unchangedRecordsNothing() async throws {
        // Arrange
        let server = try await fixture.addServer()
        let before = try fixture.auditEvents()

        // Act
        let answer = try await fixture.send(.put, HiveEndpoint.server(server.id), json: server.draft)

        // Assert
        #expect(answer.status == .ok)
        #expect(try fixture.auditEvents() == before)
    }

    @Test("Removing a server removes it and its jobs from the configuration, recording each")
    func removesServer() async throws {
        // Arrange
        let server = try await fixture.addServer()
        let job = try await fixture.addJob(to: server)

        // Act
        let answer = try await fixture.send(.delete, HiveEndpoint.server(server.id))

        // Assert
        #expect(answer.status == .noContent)
        #expect(try fixture.servers.all().isEmpty)
        #expect(try fixture.jobs.all().isEmpty)
        #expect(try await fixture.send(.get, HiveEndpoint.job(job.id)).status == .notFound)
        #expect(try fixture.auditEvents().prefix(2) == [
            .server(serverID: server.id, serverName: "Studio Web", change: .removed),
            .backupJob(jobID: job.id, serverName: "Studio Web", jobName: "Main site", change: .removed),
        ])
    }

    @Test(
        "A server that doesn't exist answers 404 and records nothing",
        arguments: [HTTPRequest.Method.get, .put, .delete],
        ["\(HiveEndpoint.servers)/\(UUID().uuidString)", "\(HiveEndpoint.servers)/not-a-uuid"]
    )
    func unknownServer(method: HTTPRequest.Method, path: String) async throws {
        // Arrange
        let before = try fixture.auditEvents()

        // Act
        let answer = try await fixture.send(method, path, json: ConfigurationSamples.server)

        // Assert
        #expect(answer.status == .notFound)
        #expect(try fixture.auditEvents() == before)
    }

    @Test(
        "A server Hive can't use is refused with the reason, saving and recording nothing",
        arguments: [
            (draft(name: " "), [ConfigurationProblem(field: .name, reason: .invalid)]),
            (draft(host: ""), [ConfigurationProblem(field: .host, reason: .invalid)]),
            (draft(host: "-oProxyCommand=sh"), [ConfigurationProblem(field: .host, reason: .invalid)]),
            (draft(host: "web example"), [ConfigurationProblem(field: .host, reason: .invalid)]),
            (draft(host: "[fd7a::1]"), [ConfigurationProblem(field: .host, reason: .invalid)]),
            (draft(port: 0), [ConfigurationProblem(field: .port, reason: .outOfRange)]),
            (draft(port: 65536), [ConfigurationProblem(field: .port, reason: .outOfRange)]),
            (draft(user: ""), [ConfigurationProblem(field: .user, reason: .invalid)]),
            (draft(user: "-l"), [ConfigurationProblem(field: .user, reason: .invalid)]),
            (draft(user: "root@web"), [ConfigurationProblem(field: .user, reason: .invalid)]),
            (draft(quotaBytes: 0), [ConfigurationProblem(field: .quota, reason: .outOfRange)]),
            (
                draft(name: "", host: "", port: 0, user: "", quotaBytes: -1),
                [
                    ConfigurationProblem(field: .name, reason: .invalid),
                    ConfigurationProblem(field: .host, reason: .invalid),
                    ConfigurationProblem(field: .port, reason: .outOfRange),
                    ConfigurationProblem(field: .user, reason: .invalid),
                    ConfigurationProblem(field: .quota, reason: .outOfRange),
                ]
            ),
        ]
    )
    func refusesInvalidServer(draft: ServerDraft, problems: [ConfigurationProblem]) async throws {
        // Arrange
        let before = try fixture.auditEvents()

        // Act
        let answer = try await fixture.send(.post, HiveEndpoint.servers, json: draft)

        // Assert
        #expect(answer.status == .unprocessableContent)
        #expect(try answer.problems == problems)
        #expect(try fixture.servers.all().isEmpty)
        #expect(try fixture.auditEvents() == before)
    }

    @Test("Hosts and users Hive can connect with are accepted", arguments: ["web-1.example.com", "100.64.0.1", "fd7a:115c::1", "web_2"])
    func acceptsHosts(host: String) async throws {
        // Arrange
        let draft = Self.draft(host: host, port: 65535, user: "deploy.user-1", quotaBytes: 1)

        // Act
        let answer = try await fixture.send(.post, HiveEndpoint.servers, json: draft)

        // Assert
        #expect(answer.status == .created)
    }

    @Test("A name another server has is refused, ignoring case, whether adding or changing")
    func refusesTakenName() async throws {
        // Arrange
        let first = try await fixture.addServer()
        var other = ConfigurationSamples.server
        other.name = "Mail"
        let second = try await fixture.addServer(other)
        var taken = ConfigurationSamples.server
        taken.name = "STUDIO web"

        // Act
        let added = try await fixture.send(.post, HiveEndpoint.servers, json: taken)
        let changed = try await fixture.send(.put, HiveEndpoint.server(second.id), json: taken)
        let renamedItself = try await fixture.send(.put, HiveEndpoint.server(first.id), json: taken)

        // Assert
        #expect(added.status == .unprocessableContent)
        #expect(try added.problems == [ConfigurationProblem(field: .name, reason: .duplicate)])
        #expect(changed.status == .unprocessableContent)
        #expect(try fixture.servers.server(id: second.id)?.name == "Mail")
        #expect(renamedItself.status == .ok)
    }

    @Test(
        "Changing a server's host, port or user clears its jobs' database passwords and its host key",
        arguments: [
            ServerConnection(host: "elsewhere.example.com", user: "backup"),
            ServerConnection(host: "web.example.com", port: 2222, user: "backup"),
            ServerConnection(host: "web.example.com", user: "root"),
        ]
    )
    func connectionChangeClearsSecrets(connection: ServerConnection) async throws {
        // Arrange
        let server = try await fixture.addServer()
        let job = try await fixture.addJob(to: server)
        try await fixture.confirmHostKey(of: server)
        var draft = server.draft
        draft.connection = connection

        // Act
        let answer = try await fixture.send(.put, HiveEndpoint.server(server.id), json: draft)

        // Assert
        #expect(answer.status == .ok)
        let changed = try answer.decoded(as: Server.self)
        #expect(changed.confirmedHostKey == nil)
        #expect(changed.sshKeyFingerprint == server.sshKeyFingerprint)
        #expect(try fixture.jobs.job(id: job.id)?.databases.map(\.hasPassword) == [false])
    }

    @Test("Changing a server's name or quota keeps its passwords and host key, and leaves other servers' alone")
    func otherChangesKeepSecrets() async throws {
        // Arrange
        let server = try await fixture.addServer()
        let job = try await fixture.addJob(to: server)
        try await fixture.confirmHostKey(of: server)
        var other = ConfigurationSamples.server
        other.name = "Mail"
        let otherServer = try await fixture.addServer(other)
        let otherJob = try await fixture.addJob(to: otherServer)
        var draft = server.draft
        draft.name = "Renamed"
        draft.quotaBytes = 1_000

        // Act
        _ = try await fixture.send(.put, HiveEndpoint.server(server.id), json: draft)
        var otherDraft = otherServer.draft
        otherDraft.connection.host = "mail.example.com"
        _ = try await fixture.send(.put, HiveEndpoint.server(otherServer.id), json: otherDraft)

        // Assert
        #expect(try fixture.servers.server(id: server.id)?.confirmedHostKey == ConfigurationSamples.hostKey.hostKeyFingerprint)
        #expect(try fixture.jobs.job(id: job.id)?.databases.map(\.hasPassword) == [true])
        #expect(try fixture.jobs.job(id: otherJob.id)?.databases.map(\.hasPassword) == [false])
    }

    @Test("A body that isn't a server is refused")
    func malformedBody() async throws {
        // Act
        let answer = try await fixture.send(.post, HiveEndpoint.servers, body: Data("{\"name\": \"Web\"}".utf8))

        // Assert
        #expect(answer.status == .badRequest)
        #expect(try fixture.servers.all().isEmpty)
    }
}
