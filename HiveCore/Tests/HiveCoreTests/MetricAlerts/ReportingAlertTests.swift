import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import ScoutProtocol
import Testing

struct ReportingAlertTests {
    private static let day: TimeInterval = 24 * 60 * 60

    /// Hive's minute checks while nothing reports, for `minutes`.
    private func checkEachMinute(_ fixture: MetricAlertFixture, for minutes: Int, on api: APIFixture? = nil) async {
        for _ in 0 ..< minutes {
            fixture.clock.advance(by: 60)
            await fixture.check(on: api)
        }
    }

    @Test("A server that stops sends one email after 3 minutes and not before, a reminder a day later, and one once it's back")
    func stoppedAndBack() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        try fixture.reportLive(for: 1)

        // Act
        await checkEachMinute(fixture, for: 3)
        let early = try fixture.subjects()
        await checkEachMinute(fixture, for: 2)
        let stopped = try fixture.alerts()
        fixture.clock.advance(by: Self.day)
        await fixture.check()
        try fixture.reportLive(for: 1)
        await fixture.check()

        // Assert
        #expect(early.isEmpty)
        #expect(try fixture.subjects() == [
            "Stopped reporting: “Studio Web”",
            "Still not reporting: “Studio Web”",
            "Reporting again: “Studio Web”",
        ])
        #expect(stopped.count == 1)
        #expect(try fixture.alerts().isEmpty)
    }

    @Test("Two servers stopping at once send one email, and one when they're both back")
    func stoppedTogether() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        try fixture.reportLive(for: 1, servers: [fixture.web, fixture.other])

        // Act
        await checkEachMinute(fixture, for: 6)
        let other = try fixture.alerts(of: fixture.other)
        try fixture.reportLive(for: 1, servers: [fixture.web])
        await fixture.check()
        let oneBack = try fixture.subjects()
        try fixture.reportLive(for: 1, servers: [fixture.web, fixture.other])
        await fixture.check()

        // Assert
        let sent = try fixture.sent()
        #expect(sent.map(\.subject) == ["2 servers stopped reporting", "2 servers reporting again"])
        #expect(sent.first?.body.contains("the Hive Mac's own connection") == true)
        #expect(other.count == 1)
        #expect(oneBack == ["2 servers stopped reporting"])
    }

    @Test("One server stopping while another reports sends an email about it alone")
    func oneOfTwoStops() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        try fixture.reportLive(for: 1, servers: [fixture.web, fixture.other])

        // Act
        for _ in 0 ..< 5 {
            try fixture.reportLive(for: 1, servers: [fixture.web])
            await fixture.check()
        }

        // Assert
        #expect(try fixture.subjects() == ["Stopped reporting: “Other”"])
        #expect(try fixture.alerts(of: fixture.web).isEmpty)
    }

    @Test("A server stopping just after another waits to be one email with it, and one stopping later is its own")
    func staggered() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        let third = try await fixture.api.addServer(ServerDraft(name: "Third", connection: nil, quotaBytes: nil))
        _ = try await fixture.api.enrollScout(for: third)
        try fixture.reportLive(for: 1, servers: [fixture.web, fixture.other, third])

        // Act
        try fixture.reportLive(for: 0.5, servers: [fixture.other, third])
        for _ in 0 ..< 10 {
            try fixture.reportLive(for: 0.5, servers: [third])
            await fixture.check()
        }
        let whileThirdReports = try fixture.subjects()
        await checkEachMinute(fixture, for: 5)

        // Assert
        #expect(whileThirdReports == ["2 servers stopped reporting"])
        #expect(try fixture.subjects() == ["2 servers stopped reporting", "Stopped reporting: “Third”"])
    }

    @Test("No server counts as stopped for a while after Hive starts")
    func graceAfterStart() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        try fixture.reportLive(for: 1)
        fixture.clock.advance(by: 60 * 60)
        let restarted = try fixture.restarted()

        // Act
        await checkEachMinute(fixture, for: 4, on: restarted)
        let inGrace = try fixture.subjects(on: restarted)
        await checkEachMinute(fixture, for: 2, on: restarted)

        // Assert
        #expect(inGrace.isEmpty)
        #expect(try fixture.subjects(on: restarted) == ["Stopped reporting: “Studio Web”"])
    }

    @Test("No server counts as stopped for a while after the Mac wakes, and the time asleep isn't taken for silence")
    func graceAfterWaking() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        try fixture.reportLive(for: 1)
        await fixture.check()

        // Act
        fixture.api.macSleep.sleep(for: .seconds(2 * 60 * 60))
        fixture.clock.advance(by: 2 * 60 * 60)
        await fixture.check()
        try fixture.reportLive(for: 1)
        await checkEachMinute(fixture, for: 2)
        let afterWaking = try fixture.subjects()
        await checkEachMinute(fixture, for: 4)

        // Assert
        #expect(afterWaking.isEmpty)
        #expect(try fixture.subjects() == ["Stopped reporting: “Studio Web”"])
    }

    @Test("No server counts as stopped for a while after the addresses Hive listens on change")
    func graceAfterAddressChange() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        try fixture.reportLive(for: 1)
        await fixture.check()

        // Act
        fixture.api.listeners.listen(on: [ListenerAddress.loopbackHost, "100.64.0.1"])
        await checkEachMinute(fixture, for: 4)
        let inGrace = try fixture.subjects()
        await checkEachMinute(fixture, for: 2)

        // Assert
        #expect(inGrace.isEmpty)
        #expect(try fixture.subjects() == ["Stopped reporting: “Studio Web”"])
    }

    @Test("A server whose clock is far ahead is emailed about as that, never as stopped, and ends once its figures are taken")
    func clockAhead() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        try fixture.reportLive(for: 1)

        // Act
        for _ in 0 ..< 6 {
            fixture.clock.advance(by: 60)
            let ahead = fixture.now + 3_600
            let outcome = try fixture.report([fixture.sample(at: ahead)], sentAt: ahead)
            #expect(outcome == .refused(.clockAhead))
            await fixture.check()
        }
        let whileAhead = try fixture.alerts()
        try fixture.reportLive(for: 1)
        await fixture.check()

        // Assert
        let sent = try fixture.sent()
        #expect(sent.map(\.subject) == ["Clock ahead: “Studio Web”"])
        #expect(sent.first?.body.contains("ahead of the Hive Mac's by about an hour") == true)
        #expect(whileAhead == [.clockAhead])
        #expect(try fixture.alerts().isEmpty)
    }

    @Test("A stopped server emailed about before Hive restarts isn't emailed again, and its return still is")
    func stoppedAcrossRestart() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        try fixture.reportLive(for: 1)
        await checkEachMinute(fixture, for: 5)

        // Act
        let restarted = try fixture.restarted()
        await checkEachMinute(fixture, for: 6, on: restarted)
        try fixture.reportLive(for: 1, on: restarted)
        await fixture.check(on: restarted)

        // Assert
        #expect(try fixture.subjects() == ["Stopped reporting: “Studio Web”"])
        #expect(try fixture.subjects(on: restarted) == ["Reporting again: “Studio Web”"])
    }

    @Test("Removing a server's metrics ends its alerts without an email")
    func removedMetrics() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        try fixture.reportLive(for: 1) { $0.setRootUsed(0.95) }
        await checkEachMinute(fixture, for: 5)

        // Act
        let answer = try await fixture.api.send(.delete, HiveEndpoint.metrics(ofServer: fixture.web.id))
        await fixture.check()

        // Assert
        #expect(answer.status == .noContent)
        #expect(try fixture.subjects() == ["Disk filling up: “/” on “Studio Web”", "Stopped reporting: “Studio Web”"])
        #expect(try AlertStore(database: fixture.api.signIn.database).all().isEmpty)
    }
}
