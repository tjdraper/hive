import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

struct FailureAlertTests {
    private static let day: TimeInterval = 24 * 60 * 60

    @Test("A failing job emails once, with the reason, naming its server and job")
    func emailsFirstFailure() async throws {
        // Arrange
        let fixture = try await AlertFixture()

        // Act
        try await fixture.failingRun()
        await fixture.check()
        try await fixture.failingRun()
        await fixture.check()

        // Assert
        let sent = try fixture.sent(startingWith: "Backup")
        #expect(sent.map(\.subject) == ["Backup failed: “Main site” on “Studio Web”"])
        let body = try #require(sent.first?.body)
        #expect(body.contains(BackupFailure.sourceMissing.emailReason))
        #expect(!body.contains(EmailRoutesTests.password))
    }

    @Test("A job that keeps failing gets a reminder once a day, however many runs fail")
    func remindsDaily() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        try await fixture.failingRun()
        await fixture.check()

        // Act
        for _ in 0 ..< 7 {
            try await fixture.failingRun(after: 4 * 60 * 60)
            await fixture.check()
        }

        // Assert
        #expect(try fixture.sent(startingWith: "Backup").map(\.subject) == [
            "Backup failed: “Main site” on “Studio Web”",
            "Backups of “Main site” on “Studio Web” are still failing",
        ])
    }

    @Test("Succeeding again sends exactly one email, and the next failure starts over")
    func recovery() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        try await fixture.failingRun()
        await fixture.check()

        // Act
        try await fixture.succeedingRun()
        await fixture.check()
        try await fixture.succeedingRun()
        await fixture.check()
        let openAfterRecovery = try fixture.store.all()
        try await fixture.failingRun()
        await fixture.check()

        // Assert
        #expect(try fixture.sent(startingWith: "Back").map(\.subject) == [
            "Backup failed: “Main site” on “Studio Web”",
            "Backing up again: “Main site” on “Studio Web”",
            "Backup failed: “Main site” on “Studio Web”",
        ])
        #expect(openAfterRecovery.isEmpty)
    }

    @Test("A failure that ends before its email was tried sends neither email")
    func failureEndedBeforeEmail() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        try await fixture.failingRun()
        await fixture.api.api.alerts.check()

        // Act
        try await fixture.succeedingRun()
        await fixture.check()

        // Assert
        #expect(try fixture.sent(startingWith: "Back").isEmpty)
        #expect(try fixture.store.all().isEmpty)
    }

    @Test("Cancelled and interrupted runs send nothing")
    func cancelledAndInterrupted() async throws {
        // Arrange
        let fixture = try await AlertFixture()

        // Act
        try fixture.recordRun(failing: .cancelled)
        try fixture.recordRun(failing: .interrupted)
        await fixture.check()

        // Assert
        #expect(try fixture.sent(startingWith: "Back").isEmpty)
    }

    @Test("A removed job's failure ends quietly")
    func removedJob() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        try await fixture.failingRun()
        await fixture.check()

        // Act
        _ = try await fixture.api.send(.delete, HiveEndpoint.job(fixture.runs.job.id))
        await fixture.check()
        fixture.clock.advance(by: Self.day)
        await fixture.check()

        // Assert
        #expect(try fixture.sent(startingWith: "Back").count == 1)
        #expect(try fixture.store.all().isEmpty)
    }

    @Test("Without email set up, each alert is still tried once and its reminder a day later")
    func withoutEmail() async throws {
        // Arrange
        let fixture = try await AlertFixture(setUpEmail: false)
        try await fixture.failingRun()
        await fixture.check()
        await fixture.check()

        // Act
        try await fixture.setUpEmail()
        fixture.clock.advance(by: Self.day)
        await fixture.check()

        // Assert
        #expect(try fixture.sent(startingWith: "Back").map(\.subject) == ["Backups of “Main site” on “Studio Web” are still failing"])
    }
}
