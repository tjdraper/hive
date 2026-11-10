import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

/// Database passwords are write-only: sealed before they're stored, and never sent back or recorded.
struct SecretExposureTests {
    private static let secret = "s3cret-Password-Never-Shown"

    private let fixture: APIFixture

    init() throws {
        fixture = try APIFixture()
    }

    @Test("No answer from any route holds a password, including refusals and the audit log")
    func noRouteReturnsPassword() async throws {
        // Arrange
        var answers: [APIAnswer] = []
        let server = try await fixture.addServer()
        let withSecret = ConfigurationSamples.job(password: Self.secret)
        let added = try await fixture.send(.post, HiveEndpoint.jobs(onServer: server.id), json: withSecret)
        answers.append(added)
        let job = try added.decoded(as: BackupJob.self)

        var replacing = job.draft
        replacing.databases[0].password = "\(Self.secret)-2"
        var refusedPassword = job.draft
        refusedPassword.databases[0].password = "\(Self.secret)\n"
        var refusedOther = job.draft
        refusedOther.name = ""
        refusedOther.databases[0].password = Self.secret
        var unknownID = ConfigurationSamples.job(name: "Other", password: Self.secret)
        unknownID.databases[0].id = UUID()
        var moved = server.draft
        moved.connection.host = "elsewhere.example.com"

        // Act
        answers.append(try await fixture.sendConfirmed(.put, HiveEndpoint.job(job.id), json: replacing))
        answers.append(try await fixture.send(.put, HiveEndpoint.job(job.id), json: refusedPassword))
        answers.append(try await fixture.send(.put, HiveEndpoint.job(job.id), json: refusedOther))
        answers.append(try await fixture.send(.post, HiveEndpoint.jobs(onServer: server.id), json: unknownID))
        answers.append(try await fixture.send(.post, HiveEndpoint.jobs(onServer: UUID()), json: withSecret))
        answers.append(try await fixture.send(.put, HiveEndpoint.job(UUID()), json: replacing))
        answers.append(try await fixture.send(.get, HiveEndpoint.job(job.id)))
        answers.append(try await fixture.send(.get, HiveEndpoint.jobs))
        answers.append(try await fixture.send(.get, HiveEndpoint.jobs(onServer: server.id)))
        answers.append(try await fixture.sendConfirmed(.put, HiveEndpoint.server(server.id), json: moved))
        answers.append(try await fixture.send(.get, HiveEndpoint.auditLog))
        answers.append(try await fixture.send(.delete, HiveEndpoint.job(job.id)))

        // Assert
        #expect(answers.map(\.status) == [
            .created, .ok, .unprocessableContent, .unprocessableContent, .unprocessableContent, .notFound, .notFound,
            .ok, .ok, .ok, .ok, .ok, .noContent,
        ])
        for answer in answers {
            #expect(answer.body.range(of: Data(Self.secret.utf8)) == nil)
        }
    }

    @Test("Passwords are stored sealed, and no table holds one in the clear")
    func storedSealed() async throws {
        // Arrange
        let server = try await fixture.addServer()

        // Act
        let job = try await fixture.addJob(ConfigurationSamples.job(password: Self.secret), to: server)
        var draft = job.draft
        draft.databases[0].password = "\(Self.secret)-2"
        _ = try await fixture.sendConfirmed(.put, HiveEndpoint.job(job.id), json: draft)

        // Assert
        let sealed = try #require(try await fixture.signIn.database.writer.read { database in
            try Data.fetchOne(database, sql: "SELECT sealedPassword FROM backupDatabase WHERE jobID = ?", arguments: [job.id])
        })
        #expect(try fixture.sealer.open(SealedSecret(data: sealed)) == Data("\(Self.secret)-2".utf8))
        for (table, value) in try fixture.everyStoredValue() {
            #expect(value.range(of: Data(Self.secret.utf8)) == nil, "\(table)")
        }
    }

    @Test("A draft printed or logged doesn't show its password")
    func draftDescriptionHidesPassword() {
        // Arrange
        let draft = ConfigurationSamples.job(password: Self.secret)

        // Act
        let printed = [String(describing: draft), String(reflecting: draft), "\(draft.databases)"]

        // Assert
        for text in printed {
            #expect(!text.contains(Self.secret))
        }
    }
}
