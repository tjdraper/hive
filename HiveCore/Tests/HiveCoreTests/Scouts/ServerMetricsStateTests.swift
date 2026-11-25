import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import ScoutProtocol
import Testing

struct ServerMetricsStateTests {
    private static func fixture(carrying scoutVersion: String? = nil) async throws -> (APIFixture, Server) {
        let fixture = try APIFixture(scoutVersion: scoutVersion)
        try fixture.setAddressOptions()
        return (fixture, try await fixture.addServer())
    }

    private static func state(of server: Server, in fixture: APIFixture) async throws -> ServerMetricsState {
        let answer = try await fixture.send(.get, HiveEndpoint.metrics(ofServer: server.id))
        guard answer.status == .ok else { throw APIFixtureError.unexpectedStatus(answer.status) }
        return try answer.decoded(as: ServerMetricsState.self)
    }

    /// Enrolls a Scout for the server, signed in as `version`.
    private static func enroll(_ server: Server, in fixture: APIFixture, version: String = "0.1.0") async throws -> TestScout {
        let scout = try await fixture.enrollScout(for: server)
        let answer = try await fixture.sendScoutSignIn(fixture.scoutSignInRequest(scout, scoutVersion: version))
        guard answer.status == .ok else { throw APIFixtureError.unexpectedStatus(answer.status) }
        return scout
    }

    @Test("A server has no metrics until a Scout enrolls, then shows what its Scout reported")
    func reportsScout() async throws {
        // Arrange
        let (fixture, server) = try await Self.fixture()
        let before = try await Self.state(of: server, in: fixture)
        _ = try await fixture.openEnrollmentWindow(for: server)
        let windowOpen = try await Self.state(of: server, in: fixture)
        let scout = try await Self.enroll(server, in: fixture)
        let now = Int64(fixture.signIn.clock.now.timeIntervalSince1970)
        let report = TestMetrics.report([TestMetrics.sample(at: now)], sentAt: now - 90)
        let token = try await fixture.scoutToken(scout)
        _ = try await fixture.send(.post, ScoutEndpoint.metrics, token: token, body: JSONEncoder().encode(report))

        // Act
        let state = try await Self.state(of: server, in: fixture)

        // Assert
        #expect(before == ServerMetricsState(hasMetrics: false, scout: nil))
        #expect(windowOpen == before)
        #expect(state.hasMetrics)
        let reported = try #require(state.scout)
        #expect(reported.enrolledAt == fixture.signIn.clock.now)
        #expect(reported.lastReportAt == fixture.signIn.clock.now)
        #expect(reported.version == "0.1.0")
        #expect(reported.platform == "linux-x86_64")
        #expect(reported.distribution == "Debian GNU/Linux 12 (bookworm)")
        #expect(reported.kernel == "6.1.0")
        #expect(reported.startedAt == now - 1_000)
        #expect(reported.clockOffsetSeconds == -90)
        #expect(reported.processesHidden == false)
        #expect(reported.update == nil)
    }

    @Test(
        "A Scout is out of date only when Hive.app carries a newer Scout, whatever Hive's own version",
        arguments: [
            ("0.1.0", "0.2.0", ScoutUpdate?.some(.newerRelease(version: "0.2.0"))),
            // Compared as numbers, not text, which would put 0.9.0 after 0.10.0.
            ("0.9.0", "0.10.0", .newerRelease(version: "0.10.0")),
            ("0.1.0", "0.1.0", nil),
            ("0.2.0", "0.1.0", nil),
            ("0.1.0", nil, nil),
        ]
    )
    func outOfDateByVersion(installed: String, carried: String?, expected: ScoutUpdate?) async throws {
        // Arrange
        let (fixture, server) = try await Self.fixture(carrying: carried)
        _ = try await Self.enroll(server, in: fixture, version: installed)

        // Act
        let state = try await Self.state(of: server, in: fixture)

        // Assert
        #expect(state.scout?.update == expected)
    }

    @Test("A Scout whose protocol Hive no longer accepts is out of date, though its version is current")
    func outOfDateByProtocol() async throws {
        // Arrange
        let (fixture, server) = try await Self.fixture(carrying: "0.1.0")
        let scout = try await fixture.enrollScout(for: server)
        let tooOld = fixture.scoutSignInRequest(scout, protocolVersion: ScoutProtocolVersion.current - 2)
        let refused = try await fixture.sendScoutSignIn(tooOld)

        // Act
        let state = try await Self.state(of: server, in: fixture)

        // Assert
        #expect(refused.status == .conflict)
        #expect(state.scout?.update == .protocolNotAccepted)
    }

    @Test("A Scout enrolled again doesn't show what the server reported before it")
    func newScoutStartsAfresh() async throws {
        // Arrange
        let (fixture, server) = try await Self.fixture()
        let first = try await Self.enroll(server, in: fixture)
        let now = Int64(fixture.signIn.clock.now.timeIntervalSince1970)
        let report = try JSONEncoder().encode(TestMetrics.report([TestMetrics.sample(at: now)]))
        _ = try await fixture.send(.post, ScoutEndpoint.metrics, token: fixture.scoutToken(first), body: report)
        fixture.signIn.clock.advance(by: 60)

        // Act
        _ = try await Self.enroll(server, in: fixture)
        let state = try await Self.state(of: server, in: fixture)

        // Assert
        let scout = try #require(state.scout)
        #expect(scout.enrolledAt == fixture.signIn.clock.now)
        #expect(scout.lastReportAt == nil)
        #expect(scout.distribution == nil)
    }

    @Test("After a new identity, a server with metrics waits for its Scout to enroll again, and one without stays without")
    func newIdentityAsksForEnrolling() async throws {
        // Arrange
        let (fixture, server) = try await Self.fixture()
        let other = try await fixture.addOtherServer()
        let scout = try await Self.enroll(server, in: fixture)

        // Act
        let answer = try await fixture.sendConfirmed(.post, HiveEndpoint.identityRegeneration)

        // Assert
        #expect(answer.status == .accepted)
        #expect(try fixture.api.metricsState.state(ofServer: server.id) == ServerMetricsState(hasMetrics: true, scout: nil))
        #expect(try fixture.api.metricsState.state(ofServer: other.id) == ServerMetricsState(hasMetrics: false, scout: nil))
        #expect(try await fixture.sendScoutSignIn(fixture.scoutSignInRequest(scout)).status == .unauthorized)
    }

    @Test("A server that doesn't exist has no metrics state")
    func unknownServer() async throws {
        // Arrange
        let (fixture, _) = try await Self.fixture()

        // Act
        let read = try await fixture.send(.get, HiveEndpoint.metrics(ofServer: UUID()))
        let removed = try await fixture.send(.delete, HiveEndpoint.metrics(ofServer: UUID()))

        // Assert
        #expect(read.status == .notFound)
        #expect(removed.status == .notFound)
    }
}
