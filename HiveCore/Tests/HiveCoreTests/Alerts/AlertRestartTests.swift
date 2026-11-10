import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct AlertRestartTests {
    private static let day: TimeInterval = 24 * 60 * 60

    /// The same Hive started again, with its store and keys.
    private static func restart(_ fixture: AlertFixture) throws -> APIFixture {
        try APIFixture(signIn: fixture.api.signIn, sealer: fixture.api.sealer)
    }

    @Test("An alert emailed before a restart isn't emailed again after it, and its reminder still comes a day later")
    func notSentTwice() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        try await fixture.failingRun()
        await fixture.check()

        // Act
        let restarted = try Self.restart(fixture)
        await fixture.check(on: restarted)
        let soon = try fixture.sent(on: restarted, startingWith: "Back")
        fixture.clock.advance(by: Self.day)
        await fixture.check(on: restarted)

        // Assert
        #expect(soon.isEmpty)
        #expect(try fixture.sent(on: restarted, startingWith: "Back").map(\.subject) == [
            "Backups of “Main site” on “Studio Web” are still failing",
        ])
    }

    @Test("An alert still owed when Hive stopped, even part way through sending, is emailed once after it starts again")
    func notForgotten() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        try await fixture.failingRun()
        await fixture.api.api.alerts.check()
        let owed = try #require(try fixture.store.nextOwed())
        try fixture.store.startEmail(for: owed, at: fixture.clock.now)

        // Act
        let restarted = try Self.restart(fixture)
        await fixture.check(on: restarted)
        await fixture.check(on: restarted)

        // Assert
        #expect(try fixture.sent(startingWith: "Back").isEmpty)
        #expect(try fixture.sent(on: restarted, startingWith: "Back").map(\.subject) == ["Backup failed: “Main site” on “Studio Web”"])
    }

    @Test("A run that finished just before a restart, before alerts were worked out for it, still sends its alert")
    func runFinishedBeforeRestart() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        try await fixture.failingRun()

        // Act
        let restarted = try Self.restart(fixture)
        await fixture.check(on: restarted)
        await fixture.check(on: restarted)

        // Assert
        #expect(try fixture.sent(on: restarted, startingWith: "Back").count == 1)
    }

    @Test("Stopping while an email waits to be tried again leaves it owed")
    func stopKeepsOwed() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        fixture.api.pauses.takeRealTime(.seconds(60))
        fixture.api.smtp.change { $0.connectFailures = [EmailSendFailure(.couldNotConnect)] }
        try await fixture.failingRun()
        let alerts = fixture.api.api.alerts
        await alerts.check()
        await alerts.mailer.sendOwed()
        while fixture.api.pauses.count < 1 {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Act
        await alerts.mailer.stop()

        // Assert
        #expect(try fixture.store.nextOwed()?.emailOwed == .first)
        #expect(try fixture.sent().isEmpty)
    }
}
