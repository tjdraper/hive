import CryptoKit
import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

/// One request to a route that changes something only with a confirmation.
struct ConfirmedRequestCase: Sendable, CustomTestStringConvertible {
    struct Request {
        let method: HTTPRequest.Method
        let path: String
        let body: Data
        /// The same request, about another object of the same kind.
        let otherPath: String
        let accepted: HTTPResponse.Status
    }

    let testDescription: String
    let reason: ConfirmationReason
    let prepare: @Sendable (APIFixture) async throws -> Request
}

struct ConfirmedRouteTests {
    static let cases: [ConfirmedRequestCase] = [
        ConfirmedRequestCase(testDescription: "changing a server's host", reason: .connectionChanged) { fixture in
            let server = try await fixture.addServer()
            var draft = server.draft
            draft.connection.host = "elsewhere.example.com"
            return try serverChange(server, draft)
        },
        ConfirmedRequestCase(testDescription: "lowering a server's quota", reason: .quotaLowered) { fixture in
            let server = try await fixture.addServer()
            var draft = server.draft
            draft.quotaBytes = 1_000
            return try serverChange(server, draft)
        },
        ConfirmedRequestCase(testDescription: "lowering a job's tiers", reason: .retentionLowered) { fixture in
            let job = try await fixture.addJob(to: fixture.addServer())
            var draft = job.draft
            draft.retention.dailySnapshots -= 1
            return try jobChange(job, draft)
        },
        ConfirmedRequestCase(testDescription: "replacing a database password", reason: .passwordReplaced) { fixture in
            let job = try await fixture.addJob(to: fixture.addServer())
            var draft = job.draft
            draft.databases[0].password = "another password"
            return try jobChange(job, draft)
        },
        ConfirmedRequestCase(testDescription: "confirming a changed host key", reason: .hostKeyReplaced) { fixture in
            let server = try await fixture.addServer()
            try await fixture.confirmHostKey(of: server)
            let newKey = SSHKeyPair().publicKey
            fixture.ssh.setScan(.found(newKey))
            _ = try await fixture.send(.post, HiveEndpoint.hostKeyScan(onServer: server.id))
            return ConfirmedRequestCase.Request(
                method: .put,
                path: HiveEndpoint.hostKey(onServer: server.id),
                body: try JSONEncoder().encode(HostKeyConfirmation(fingerprint: newKey.fingerprint)),
                otherPath: HiveEndpoint.hostKey(onServer: UUID()),
                accepted: .ok
            )
        },
        ConfirmedRequestCase(testDescription: "replacing Hive's SSH key", reason: .sshKeyReplaced) { fixture in
            let server = try await fixture.addServer()
            return ConfirmedRequestCase.Request(
                method: .post,
                path: HiveEndpoint.sshKey(onServer: server.id),
                body: Data(),
                otherPath: HiveEndpoint.sshKey(onServer: UUID()),
                accepted: .created
            )
        },
        ConfirmedRequestCase(testDescription: "deleting a snapshot", reason: .snapshotsDeleted) { fixture in
            let snapshot = try await fixture.addCatalogedSnapshot()
            return deletion(HiveEndpoint.snapshot(snapshot.id), other: HiveEndpoint.snapshot(UUID()))
        },
        ConfirmedRequestCase(testDescription: "deleting a job's snapshots", reason: .snapshotsDeleted) { fixture in
            let snapshot = try await fixture.addCatalogedSnapshot()
            return deletion(HiveEndpoint.snapshots(ofJob: snapshot.jobID), other: HiveEndpoint.snapshots(ofJob: UUID()))
        },
        ConfirmedRequestCase(testDescription: "deleting a server's snapshots", reason: .snapshotsDeleted) { fixture in
            let snapshot = try await fixture.addCatalogedSnapshot()
            return deletion(HiveEndpoint.snapshots(ofServer: snapshot.serverID), other: HiveEndpoint.snapshots(ofServer: UUID()))
        },
        ConfirmedRequestCase(testDescription: "regenerating the identity", reason: .identityRegenerated) { _ in
            ConfirmedRequestCase.Request(
                method: .post,
                path: HiveEndpoint.identityRegeneration,
                body: Data(),
                otherPath: HiveEndpoint.identityRegeneration + "/",
                accepted: .accepted
            )
        },
        ConfirmedRequestCase(testDescription: "changing the SMTP host", reason: .emailHostChanged) { fixture in
            let settings = EmailRoutesTests.settings
            _ = try await fixture.send(.put, HiveEndpoint.email, json: EmailSettingsChange(settings: settings, password: "password"))
            var moved = settings
            moved.host = "smtp.elsewhere.example"
            return ConfirmedRequestCase.Request(
                method: .put,
                path: HiveEndpoint.email,
                body: try JSONEncoder().encode(EmailSettingsChange(settings: moved, password: "another password")),
                otherPath: HiveEndpoint.email + "/",
                accepted: .ok
            )
        },
        ConfirmedRequestCase(testDescription: "saving a recovery key", reason: .recoveryKeyChanged) { _ in
            ConfirmedRequestCase.Request(
                method: .put,
                path: HiveEndpoint.recoveryKey,
                body: try JSONEncoder().encode(RecoveryKeyChange(publicKey: RecoveryKey().publicKey.rawRepresentation)),
                otherPath: HiveEndpoint.recoveryKey + "/",
                accepted: .ok
            )
        },
        ConfirmedRequestCase(testDescription: "starting retention after a restore", reason: .retentionStarted) { fixture in
            try await fixture.signIn.database.writer.write { database in
                try database.execute(sql: "UPDATE hive SET retentionPausedSince = ?", arguments: [fixture.signIn.clock.now])
            }
            return deletion(HiveEndpoint.retentionPause, other: HiveEndpoint.retentionPause + "/", accepted: .noContent)
        },
        ConfirmedRequestCase(testDescription: "rotating SSH keys", reason: .sshKeysRotated) { _ in
            ConfirmedRequestCase.Request(
                method: .post,
                path: HiveEndpoint.sshKeyRotation,
                body: Data(),
                otherPath: HiveEndpoint.sshKeyRotation + "/",
                accepted: .accepted
            )
        },
    ]

    private static func serverChange(_ server: Server, _ draft: ServerDraft) throws -> ConfirmedRequestCase.Request {
        ConfirmedRequestCase.Request(
            method: .put,
            path: HiveEndpoint.server(server.id),
            body: try JSONEncoder().encode(draft),
            otherPath: HiveEndpoint.server(UUID()),
            accepted: .ok
        )
    }

    private static func jobChange(_ job: BackupJob, _ draft: BackupJobDraft) throws -> ConfirmedRequestCase.Request {
        ConfirmedRequestCase.Request(
            method: .put,
            path: HiveEndpoint.job(job.id),
            body: try JSONEncoder().encode(draft),
            otherPath: HiveEndpoint.job(UUID()),
            accepted: .ok
        )
    }

    private static func deletion(_ path: String, other: String, accepted: HTTPResponse.Status = .accepted) -> ConfirmedRequestCase.Request {
        ConfirmedRequestCase.Request(method: .delete, path: path, body: Data(), otherPath: other, accepted: accepted)
    }

    /// Every change is audited in the same transaction, so an unchanged audit log means nothing changed.
    private static func expectNothingChanged(_ fixture: APIFixture, since before: [AuditEvent]) throws {
        #expect(try fixture.auditEvents() == before)
        #expect(try fixture.signIn.devices.all().count == 1)
        #expect(!fixture.restart.isRequested)
    }

    @Test("Without a confirmation, a route asks for one and changes nothing", arguments: cases)
    func refusesUnconfirmed(change: ConfirmedRequestCase) async throws {
        // Arrange
        let fixture = try APIFixture()
        let request = try await change.prepare(fixture)
        let before = try fixture.auditEvents()

        // Act
        let answer = try await fixture.send(request.method, request.path, body: request.body)

        // Assert
        #expect(answer.status == .preconditionRequired)
        #expect(try answer.confirmationReasons.contains(change.reason))
        try Self.expectNothingChanged(fixture, since: before)
    }

    @Test("A signature for another action, object or change, or by another key, is refused", arguments: cases)
    func refusesWrongSignature(change: ConfirmedRequestCase) async throws {
        // Arrange
        let fixture = try APIFixture()
        let request = try await change.prepare(fixture)
        let before = try fixture.auditEvents()
        let otherMethod: HTTPRequest.Method = request.method == .put ? .post : .put
        let signedElsewhere = [
            try fixture.confirmation(otherMethod, request.path, body: request.body),
            try fixture.confirmation(request.method, request.otherPath, body: request.body),
            try fixture.confirmation(request.method, request.path, body: request.body + Data("x".utf8)),
            try fixture.confirmation(request.method, request.path, body: request.body, key: fixture.signIn.deviceKey),
            try fixture.confirmation(request.method, request.path, body: request.body, key: P256.Signing.PrivateKey()),
        ]

        for confirmation in signedElsewhere {
            // Act
            let answer = try await fixture.send(request.method, request.path, body: request.body, confirmation: confirmation)

            // Assert
            #expect(answer.status == .forbidden)
            #expect(try answer.confirmationRefusal == .badSignature)
        }
        try Self.expectNothingChanged(fixture, since: before)
    }

    @Test("A nonce Hive didn't issue, one that expired, or one already used is refused", arguments: cases)
    func refusesBadNonce(change: ConfirmedRequestCase) async throws {
        // Arrange
        let fixture = try APIFixture()
        let request = try await change.prepare(fixture)
        let before = try fixture.auditEvents()
        let made = try fixture.confirmation(request.method, request.path, body: request.body, nonce: Data(repeating: 1, count: 57))
        let expiring = try fixture.confirmation(request.method, request.path, body: request.body)
        fixture.signIn.clock.advance(by: ConfirmationVerifier.nonceLifetime + 1)

        // Act
        let notIssued = try await fixture.send(request.method, request.path, body: request.body, confirmation: made)
        let expired = try await fixture.send(request.method, request.path, body: request.body, confirmation: expiring)

        // Assert
        #expect(try notIssued.confirmationRefusal == .nonceNotIssued)
        #expect(try expired.confirmationRefusal == .nonceExpired)
        try Self.expectNothingChanged(fixture, since: before)
    }

    @Test("A good confirmation is accepted once, and its nonce can't be used again", arguments: cases)
    func acceptsOnce(change: ConfirmedRequestCase) async throws {
        // Arrange
        let fixture = try APIFixture()
        let request = try await change.prepare(fixture)
        let confirmation = try fixture.confirmation(request.method, request.path, body: request.body)

        // Act
        let first = try await fixture.send(request.method, request.path, body: request.body, confirmation: confirmation)
        // Regenerating the identity unpairs the device, which can't send anything more.
        let isStillPaired = try !fixture.signIn.devices.all().isEmpty
        let again = isStillPaired
            ? try await fixture.send(request.method, request.path, body: request.body, confirmation: confirmation)
            : nil

        // Assert
        #expect(first.status == request.accepted)
        if let again {
            #expect(again.status == .forbidden)
            #expect(try again.confirmationRefusal == .nonceReused)
        }
    }

    @Test("A device without a confirmation key can't confirm anything")
    func refusesWithoutKey() async throws {
        // Arrange
        let fixture = try APIFixture()
        try await fixture.signIn.database.writer.write { database in
            try database.execute(sql: "UPDATE device SET confirmationPublicKey = NULL")
        }
        let server = try await fixture.addServer()
        var draft = server.draft
        draft.connection.host = "elsewhere.example.com"
        let body = try JSONEncoder().encode(draft)
        let path = HiveEndpoint.server(server.id)

        // Act
        let answer = try await fixture.send(.put, path, body: body, confirmation: fixture.confirmation(.put, path, body: body))

        // Assert
        #expect(answer.status == .forbidden)
        #expect(try answer.confirmationRefusal == .noConfirmationKey)
        #expect(try fixture.servers.server(id: server.id) == server)
    }

    @Test("A malformed confirmation header is refused")
    func refusesMalformedHeader() async throws {
        // Arrange
        let fixture = try APIFixture()
        let server = try await fixture.addServer()
        var headers = try fixture.headers(token: fixture.token())
        headers[try #require(HTTPFields.Element.Name(ConfirmationProof.headerName))] = "not a confirmation"

        // Act
        let status = try await fixture.application.test(.router) { [headers] client in
            try await client.execute(uri: HiveEndpoint.sshKey(onServer: server.id), method: .post, headers: headers) { $0.status }
        }

        // Assert
        #expect(status == .forbidden)
    }
}

extension APIFixture {
    /// A complete snapshot of a new job, in the catalog only, on a chosen drive that isn't mounted, so
    /// a deletion asked for waits.
    func addCatalogedSnapshot() async throws -> SnapshotRecord {
        let server = try await addServer()
        let job = try await addJob(to: server)
        let volumeUUID = UUID()
        try BackupDriveStore(database: signIn.database).choose(
            BackupDriveIdentity(volumeUUID: volumeUUID, name: "Test Drive"),
            by: signIn.device.id,
            at: signIn.clock.now
        )
        let record = SnapshotRecord(
            id: UUID(),
            jobID: job.id,
            serverID: server.id,
            driveUUID: volumeUUID.uuidString,
            serverFolder: "web-1",
            jobFolder: "site-1",
            folder: "2026-11-06T182353Z",
            state: .complete,
            startedAt: signIn.clock.now,
            completedAt: signIn.clock.now
        )
        try SnapshotCatalog(database: signIn.database).add(record)
        return record
    }
}
