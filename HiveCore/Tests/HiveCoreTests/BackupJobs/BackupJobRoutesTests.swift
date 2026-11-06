import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct BackupJobRoutesTests {
    private let fixture: APIFixture
    private let server: Server

    private static let postgres = DatabaseSettings(kind: .postgres, location: .host, user: "app", name: "app")

    init() async throws {
        fixture = try APIFixture()
        server = try await fixture.addServer()
    }

    private static func event(_ jobID: UUID, jobName: String = "Main site", _ change: BackupJobChange) -> AuditEvent {
        .backupJob(jobID: jobID, serverName: "Studio Web", jobName: jobName, change: change)
    }

    @Test("A job is added, then read back as saved, with its times in order and its password only said to be set")
    func addsJob() async throws {
        // Arrange
        var draft = ConfigurationSamples.job()
        draft.directories[0].path = "/var/www/site/uploads/"

        // Act
        let added = try await fixture.addJob(draft, to: server)

        // Assert
        #expect(added.serverID == server.id)
        #expect(added.name == "Main site")
        #expect(added.directories == [
            BackupDirectory(path: "/var/www/site/uploads", folder: "uploads"),
            BackupDirectory(path: "/var/lib/docker/volumes/galleries/_data", folder: "images/galleries"),
        ])
        #expect(added.databases.map(\.settings) == [ConfigurationSamples.database])
        #expect(added.databases.map(\.hasPassword) == [true])
        #expect(added.times == [TimeOfDay(hour: 2, minute: 30), TimeOfDay(hour: 14, minute: 0)])
        #expect(added.retention == RetentionTiers(dailySnapshots: 14, monthlySnapshots: 12))
        #expect(try await fixture.send(.get, HiveEndpoint.job(added.id)).decoded(as: BackupJob.self) == added)
        #expect(try await fixture.send(.get, HiveEndpoint.jobs).decoded(as: [BackupJob].self) == [added])
        #expect(try await fixture.send(.get, HiveEndpoint.jobs(onServer: server.id)).decoded(as: [BackupJob].self) == [added])
        #expect(try fixture.auditEvents().first == Self.event(added.id, .added))
    }

    @Test("A database on the host, a Postgres one, and one with no password are kept as sent")
    func addsDatabaseKinds() async throws {
        // Arrange
        var draft = ConfigurationSamples.job()
        draft.databases = [
            BackupDatabaseDraft(id: nil, settings: Self.postgres, password: nil),
            BackupDatabaseDraft(
                id: nil,
                settings: DatabaseSettings(kind: .mysql, location: .container(serviceName: "smrc_db"), user: "smrc_api", name: "smrc_api"),
                password: "p@ss w0rd \"quoted\" é"
            ),
        ]

        // Act
        let added = try await fixture.addJob(draft, to: server)

        // Assert
        #expect(added.databases.map(\.settings) == draft.databases.map(\.settings))
        #expect(added.databases.map(\.hasPassword) == [false, true])
    }

    @Test("Each server lists only its own jobs, and a server that doesn't exist answers 404")
    func listsJobsByServer() async throws {
        // Arrange
        var other = ConfigurationSamples.server
        other.name = "Mail"
        let otherServer = try await fixture.addServer(other)
        let job = try await fixture.addJob(to: server)
        let otherJob = try await fixture.addJob(ConfigurationSamples.job(name: "Webmail"), to: otherServer)

        // Act
        let jobs = try await fixture.send(.get, HiveEndpoint.jobs(onServer: server.id)).decoded(as: [BackupJob].self)
        let all = try await fixture.send(.get, HiveEndpoint.jobs).decoded(as: [BackupJob].self)
        let unknown = try await fixture.send(.get, HiveEndpoint.jobs(onServer: UUID()))

        // Assert
        #expect(jobs.map(\.id) == [job.id])
        #expect(Set(all.map(\.id)) == [job.id, otherJob.id])
        #expect(unknown.status == .notFound)
    }

    @Test("Adding a job to a server that doesn't exist answers 404 and saves nothing")
    func addToUnknownServer() async throws {
        // Act
        let answer = try await fixture.send(.post, HiveEndpoint.jobs(onServer: UUID()), json: ConfigurationSamples.job())

        // Assert
        #expect(answer.status == .notFound)
        #expect(try fixture.jobs.all().isEmpty)
    }

    @Test("Changing each part of a job saves it and records each change")
    func changesJob() async throws {
        // Arrange
        let job = try await fixture.addJob(to: server)
        var draft = job.draft
        draft.name = "Main site 2"
        draft.directories.removeLast()
        draft.databases[0].settings.user = "site_backup"
        draft.times = [TimeOfDay(hour: 3, minute: 15)]
        draft.retention = RetentionTiers(dailySnapshots: 30, monthlySnapshots: 24)

        // Act
        let answer = try await fixture.send(.put, HiveEndpoint.job(job.id), json: draft)

        // Assert
        #expect(answer.status == .ok)
        let changed = try answer.decoded(as: BackupJob.self)
        #expect(changed.draft == draft)
        #expect(try fixture.jobs.job(id: job.id) == changed)
        let change = { (change: BackupJobChange) in Self.event(job.id, jobName: "Main site 2", change) }
        var user = ConfigurationSamples.database
        user.user = "site_backup"
        #expect(try fixture.auditEvents().prefix(5) == [
            change(.retention(old: job.retention, new: draft.retention)),
            change(.times(old: job.times, new: draft.times)),
            change(.databases(old: [ConfigurationSamples.database], new: [user])),
            change(.directories(old: job.directories, new: draft.directories)),
            change(.renamed(old: "Main site", new: "Main site 2")),
        ])
    }

    @Test("Sending a job unchanged keeps its password and records nothing")
    func unchangedRecordsNothing() async throws {
        // Arrange
        let job = try await fixture.addJob(to: server)
        let before = try fixture.auditEvents()

        // Act
        let answer = try await fixture.send(.put, HiveEndpoint.job(job.id), json: job.draft)

        // Assert
        #expect(answer.status == .ok)
        #expect(try answer.decoded(as: BackupJob.self) == job)
        #expect(try fixture.auditEvents() == before)
    }

    @Test("A new password replaces the old one, and is recorded without its value")
    func replacesPassword() async throws {
        // Arrange
        let job = try await fixture.addJob(to: server)
        var draft = job.draft
        draft.databases[0].password = "a new password"

        // Act
        let answer = try await fixture.send(.put, HiveEndpoint.job(job.id), json: draft)

        // Assert
        #expect(answer.status == .ok)
        #expect(try openedPasswords(of: job.id) == [Data("a new password".utf8)])
        #expect(try fixture.auditEvents().first == Self.event(job.id, .databasePassword(databaseName: "site")))
    }

    @Test("A database keeps its password through a change to its other settings and to its place in the list")
    func keepsPasswordThroughChanges() async throws {
        // Arrange
        let job = try await fixture.addJob(to: server)
        var draft = job.draft
        draft.databases[0].settings.location = .host
        draft.databases.insert(
            BackupDatabaseDraft(id: nil, settings: Self.postgres, password: "second"),
            at: 0
        )

        // Act
        let changed = try await fixture.send(.put, HiveEndpoint.job(job.id), json: draft).decoded(as: BackupJob.self)

        // Assert
        #expect(changed.databases[1].id == job.databases[0].id)
        #expect(try openedPasswords(of: job.id) == [Data("second".utf8), Data(ConfigurationSamples.password.utf8)])
    }

    @Test("A database ID from another job is refused, so a password can't move to another server")
    func refusesDatabaseFromAnotherJob() async throws {
        // Arrange
        let job = try await fixture.addJob(to: server)
        var other = ConfigurationSamples.server
        other.name = "Elsewhere"
        other.connection.host = "attacker.example.com"
        let otherServer = try await fixture.addServer(other)
        let otherJob = try await fixture.addJob(ConfigurationSamples.job(password: nil), to: otherServer)
        var stealing = otherJob.draft
        stealing.databases[0].id = job.databases[0].id
        var adding = ConfigurationSamples.job(password: nil)
        adding.databases[0].id = job.databases[0].id

        // Act
        let changed = try await fixture.send(.put, HiveEndpoint.job(otherJob.id), json: stealing)
        let added = try await fixture.send(.post, HiveEndpoint.jobs(onServer: otherServer.id), json: adding)

        // Assert
        for answer in [changed, added] {
            #expect(answer.status == .unprocessableContent)
            #expect(try answer.problems == [ConfigurationProblem(field: .database, index: 0, reason: .unknown)])
        }
        #expect(try fixture.jobs.job(id: otherJob.id) == otherJob)
        #expect(try fixture.jobs.jobs(onServer: otherServer.id)?.count == 1)
    }

    @Test("A name another job on the same server has is refused, ignoring case, but another server's jobs don't count")
    func refusesTakenName() async throws {
        // Arrange
        _ = try await fixture.addJob(to: server)
        var other = ConfigurationSamples.server
        other.name = "Mail"
        let otherServer = try await fixture.addServer(other)

        // Act
        let taken = ConfigurationSamples.job(name: "MAIN SITE")
        let sameServer = try await fixture.send(.post, HiveEndpoint.jobs(onServer: server.id), json: taken)
        let otherServerAnswer = try await fixture.send(.post, HiveEndpoint.jobs(onServer: otherServer.id), json: taken)

        // Assert
        #expect(sameServer.status == .unprocessableContent)
        #expect(try sameServer.problems == [ConfigurationProblem(field: .name, reason: .duplicate)])
        #expect(otherServerAnswer.status == .created)
    }

    @Test("Removing a job removes its configuration only, recording it, and leaves its server")
    func removesJob() async throws {
        // Arrange
        let job = try await fixture.addJob(to: server)

        // Act
        let answer = try await fixture.send(.delete, HiveEndpoint.job(job.id))

        // Assert
        #expect(answer.status == .noContent)
        #expect(try await fixture.send(.get, HiveEndpoint.job(job.id)).status == .notFound)
        #expect(try fixture.servers.server(id: server.id) != nil)
        #expect(try fixture.auditEvents().first == Self.event(job.id, .removed))
    }

    @Test(
        "A job that doesn't exist answers 404 and records nothing",
        arguments: [HTTPRequest.Method.get, .put, .delete],
        ["\(HiveEndpoint.jobs)/\(UUID().uuidString)", "\(HiveEndpoint.jobs)/not-a-uuid"]
    )
    func unknownJob(method: HTTPRequest.Method, path: String) async throws {
        // Arrange
        let before = try fixture.auditEvents()

        // Act
        let answer = try await fixture.send(method, path, json: ConfigurationSamples.job())

        // Assert
        #expect(answer.status == .notFound)
        #expect(try fixture.auditEvents() == before)
    }

    @Test("A job Hive can't use is refused with every problem, whether adding or changing, saving and recording nothing")
    func refusesInvalidJob() async throws {
        // Arrange
        let job = try await fixture.addJob(to: server)
        let before = try fixture.auditEvents()
        var draft = job.draft
        draft.name = ""
        draft.directories = [BackupDirectory(path: "var/www", folder: "../www")]
        draft.times = []
        draft.retention = RetentionTiers(dailySnapshots: 0, monthlySnapshots: 0)

        // Act
        let changed = try await fixture.send(.put, HiveEndpoint.job(job.id), json: draft)
        let added = try await fixture.send(.post, HiveEndpoint.jobs(onServer: server.id), json: draft)

        // Assert
        for answer in [changed, added] {
            #expect(answer.status == .unprocessableContent)
            #expect(try answer.problems == [
                ConfigurationProblem(field: .name, reason: .invalid),
                ConfigurationProblem(field: .directoryPath, index: 0, reason: .notAbsolute),
                ConfigurationProblem(field: .directoryFolder, index: 0, reason: .dotPart),
                ConfigurationProblem(field: .times, reason: .missing),
                ConfigurationProblem(field: .dailySnapshots, reason: .outOfRange),
            ])
        }
        #expect(try fixture.jobs.all() == [job])
        #expect(try fixture.auditEvents() == before)
    }

    @Test("A body that isn't a job is refused")
    func malformedBody() async throws {
        // Act
        let answer = try await fixture.send(.post, HiveEndpoint.jobs(onServer: server.id), body: Data("{\"name\": \"Site\"}".utf8))

        // Assert
        #expect(answer.status == .badRequest)
        #expect(try fixture.jobs.all().isEmpty)
    }

    private func openedPasswords(of jobID: UUID) throws -> [Data] {
        let sealed = try fixture.signIn.database.writer.read { database in
            try Data?.fetchAll(
                database,
                sql: "SELECT sealedPassword FROM backupDatabase WHERE jobID = ? ORDER BY position",
                arguments: [jobID]
            )
        }
        return try sealed.map { try fixture.sealer.open(SealedSecret(data: #require($0))) }
    }
}
