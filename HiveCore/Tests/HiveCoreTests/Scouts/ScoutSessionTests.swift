import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import ScoutProtocol
import Testing

struct ScoutSessionTests {
    private let fixture: APIFixture
    private let server: Server
    private let scout: TestScout

    init() async throws {
        fixture = try APIFixture()
        try fixture.setAddressOptions()
        server = try await fixture.addServer()
        scout = try await fixture.enrollScout(for: server)
    }

    @Test("A Scout signs in through the devices' sign-in route, to a session for its own server, recording what it reported")
    func signsIn() async throws {
        // Arrange
        let other = try await fixture.addOtherServer()
        let otherScout = try await fixture.enrollScout(for: other)

        // Act
        let answer = try await fixture.send(.get, ScoutEndpoint.session, token: fixture.scoutToken(scout))
        let otherAnswer = try await fixture.send(.get, ScoutEndpoint.session, token: fixture.scoutToken(otherScout))

        // Assert
        #expect(try answer.decoded(as: ScoutSessionCheck.self).serverID == server.id)
        #expect(try otherAnswer.decoded(as: ScoutSessionCheck.self).serverID == other.id)
        let record = try #require(try fixture.api.scouts.scout(forServer: server.id))
        #expect(record.lastSeenAt == fixture.signIn.clock.now)
        #expect(record.version == "0.1.0")
        #expect(record.platform == "linux-x86_64")
    }

    @Test("A Scout's sign-in is refused with another key, a reused challenge, or a device's statement")
    func badSignInsRefused() async throws {
        // Arrange
        let otherKey = fixture.scoutSignInRequest(scout, key: P256.Signing.PrivateKey())
        let reused = fixture.scoutSignInRequest(scout)
        _ = try await fixture.sendScoutSignIn(reused)
        let challenge = fixture.signIn.workflow.issueChallenge().challenge
        let deviceStatement = SignInStatement.bytes(hiveID: fixture.signIn.hiveID, deviceID: scout.enrollment.scoutID, challenge: challenge)
        let asDevice = ScoutSignInRequest(
            scoutID: scout.enrollment.scoutID,
            challenge: challenge,
            signature: try scout.key.signature(for: deviceStatement).rawRepresentation,
            protocolVersion: ScoutProtocolVersion.current,
            scoutVersion: "0.1.0",
            platform: "linux-x86_64"
        )

        // Act
        let answers = [
            try await fixture.sendScoutSignIn(otherKey),
            try await fixture.sendScoutSignIn(reused),
            try await fixture.sendScoutSignIn(asDevice),
        ]

        // Assert
        #expect(answers.map(\.status) == [.unauthorized, .unauthorized, .unauthorized])
    }

    @Test("A Scout on the protocol before the current one signs in, and one older is told to update")
    func protocolVersions() async throws {
        // Act
        let current = ScoutProtocolVersion.current
        let previous = try await fixture.sendScoutSignIn(fixture.scoutSignInRequest(scout, protocolVersion: current - 1))
        let tooOld = try await fixture.sendScoutSignIn(fixture.scoutSignInRequest(scout, protocolVersion: current - 2))

        // Assert
        #expect(previous.status == .ok)
        #expect(tooOld.status == .conflict)
        #expect(try tooOld.decoded(as: ScoutProtocolMismatch.self).hiveProtocolVersion == ScoutProtocolVersion.current)
    }

    @Test(
        "A Scout's session is refused on every device route, and on paths the router might read as one",
        arguments: [
            (HiveEndpoint.overview, HTTPRequest.Method.get),
            (HiveEndpoint.devices, .get),
            (HiveEndpoint.settings, .get),
            (HiveEndpoint.settings, .put),
            (HiveEndpoint.auditLog, .get),
            (HiveEndpoint.servers, .get),
            (HiveEndpoint.servers, .post),
            (HiveEndpoint.jobs, .get),
            (HiveEndpoint.jobStatus, .get),
            (HiveEndpoint.jobLog, .get),
            (HiveEndpoint.liveUpdates, .get),
            (HiveEndpoint.pairingWindow, .post),
            (HiveEndpoint.confirmationChallenge, .post),
            (HiveEndpoint.recoveryFile, .get),
            (HiveEndpoint.backupDrive, .get),
            ("/scout/../servers", .get),
            ("/scout/%2e%2e/servers", .get),
            ("//scout/session", .get),
            ("/scout/session/", .get),
            (ScoutEndpoint.session, .post),
        ]
    )
    func scoutSessionRefusedOnDeviceRoutes(path: String, method: HTTPRequest.Method) async throws {
        // Arrange
        let token = try await fixture.scoutToken(scout)
        let before = try fixture.auditEvents()

        // Act
        let answer = try await fixture.send(method, path, token: token, body: Data("{}".utf8))

        // Assert
        #expect(answer.status == .forbidden)
        #expect(answer.body.isEmpty)
        #expect(try fixture.auditEvents() == before)
    }

    @Test("A Scout's session is refused on its own server's device routes too")
    func scoutSessionRefusedOnItsServer() async throws {
        // Arrange
        let token = try await fixture.scoutToken(scout)
        let paths: [(String, HTTPRequest.Method)] = [
            (HiveEndpoint.server(server.id), .get),
            (HiveEndpoint.server(server.id), .delete),
            (HiveEndpoint.sshKey(onServer: server.id), .get),
            (HiveEndpoint.enrollmentWindow(forServer: server.id), .post),
            (HiveEndpoint.metrics(ofServer: server.id), .get),
            (HiveEndpoint.metrics(ofServer: server.id), .delete),
            (HiveEndpoint.metricsSummary, .get),
            (HiveEndpoint.metricsSeries(ofServer: server.id, from: 0, to: 3_600, figures: [.cpuUser]), .get),
            (HiveEndpoint.processes(ofServer: server.id, at: 0), .get),
            (HiveEndpoint.containers(ofServer: server.id, at: 0), .get),
            (HiveEndpoint.containerSeries(ofServer: server.id, from: 0, to: 3_600), .get),
            (HiveEndpoint.filesystemForecasts(ofServer: server.id), .get),
            (HiveEndpoint.backupRunMarks(ofServer: server.id, from: 0, to: 3_600), .get),
        ]

        for (path, method) in paths {
            // Act
            let answer = try await fixture.send(method, path, token: token)

            // Assert
            #expect(answer.status == .forbidden, "\(method) \(path)")
        }
        #expect(try fixture.api.scouts.scout(forServer: server.id) != nil)
        #expect(try fixture.servers.all() == [server])
    }

    @Test(
        "A device's session is refused on every Scout route, however the path is written",
        arguments: [ScoutEndpoint.session, "//scout/session", "/scout/session/", "/scout/anything", "/%73cout/session"]
    )
    func deviceSessionRefusedOnScoutRoutes(path: String) async throws {
        // Arrange
        let token = try fixture.token()

        // Act
        let answer = try await fixture.send(.get, path, token: token)

        // Assert
        #expect(answer.status != .ok)
        #expect(answer.body.isEmpty || (try? answer.decoded(as: ScoutSessionCheck.self)) == nil)
    }

    @Test("Removing a server's metrics stops its Scout signing in and ends its open session at once, and is recorded")
    func removingMetricsRevokes() async throws {
        // Arrange
        let token = try await fixture.scoutToken(scout)

        // Act
        let removed = try await fixture.send(.delete, HiveEndpoint.metrics(ofServer: server.id))

        // Assert
        #expect(removed.status == .noContent)
        #expect(try await fixture.send(.get, ScoutEndpoint.session, token: token).status == .unauthorized)
        #expect(try await fixture.sendScoutSignIn(fixture.scoutSignInRequest(scout)).status == .unauthorized)
        #expect(try fixture.auditEvents().first == .scout(serverID: server.id, serverName: server.name, change: .removed))
        #expect(try fixture.api.metricsState.state(ofServer: server.id) == ServerMetricsState(hasMetrics: false, scout: nil))
        #expect(try await fixture.send(.delete, HiveEndpoint.metrics(ofServer: server.id)).status == .notFound)
    }

    @Test("Removing the server removes its Scout and ends its session, leaving other servers' Scouts")
    func removingServerRevokes() async throws {
        // Arrange
        let other = try await fixture.addOtherServer()
        let otherScout = try await fixture.enrollScout(for: other)
        let token = try await fixture.scoutToken(scout)
        let otherToken = try await fixture.scoutToken(otherScout)

        // Act
        let removed = try await fixture.send(.delete, HiveEndpoint.server(server.id))

        // Assert
        #expect(removed.status == .noContent)
        #expect(try fixture.api.scouts.scout(forServer: server.id) == nil)
        #expect(try await fixture.send(.get, ScoutEndpoint.session, token: token).status == .unauthorized)
        #expect(try await fixture.sendScoutSignIn(fixture.scoutSignInRequest(scout)).status == .unauthorized)
        #expect(try await fixture.send(.get, ScoutEndpoint.session, token: otherToken).status == .ok)
    }

    @Test("A Scout's session runs out like a device's")
    func sessionExpires() async throws {
        // Arrange
        let token = try await fixture.scoutToken(scout)
        fixture.signIn.clock.advance(by: SessionStore.lifetime)

        // Act
        let answer = try await fixture.send(.get, ScoutEndpoint.session, token: token)

        // Assert
        #expect(answer.status == .unauthorized)
    }
}
