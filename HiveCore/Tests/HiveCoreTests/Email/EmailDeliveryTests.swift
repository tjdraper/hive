import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import OSLog
import Testing

struct EmailDeliveryTests {
    private let fixture: APIFixture

    init() async throws {
        fixture = try APIFixture()
        let change = EmailSettingsChange(settings: EmailRoutesTests.settings, password: EmailRoutesTests.password)
        _ = try await fixture.send(.put, HiveEndpoint.email, json: change)
    }

    private static let message = EmailMessage(subject: "Backup failed", body: "A job failed.")

    @Test("The delay before each try grows, up to an hour")
    func delays() {
        // Act
        let delays = (1 ... 9).map(EmailDelivery.delay(afterFailures:))

        // Assert
        #expect(delays == [60, 120, 240, 480, 960, 1920, 3600, 3600, 3600])
    }

    @Test("While the provider can't be reached, it tries again after each delay, and sends once it can")
    func retriesUntilSent() async throws {
        // Arrange
        let unreachable = EmailSendFailure(.couldNotConnect)
        let notNow = EmailSendFailure(.unexpectedReply, reply: SMTPReply(code: 421, lines: ["Service not available"]))
        fixture.smtp.change { $0.connectFailures = [unreachable, unreachable, notNow, EmailSendFailure(.timedOut)] }
        let started = fixture.signIn.clock.now

        // Act
        let outcome = await fixture.api.emailDelivery.deliver(Self.message)

        // Assert
        #expect(outcome == .sent)
        #expect(fixture.pauses.count == 4)
        #expect(fixture.signIn.clock.now.timeIntervalSince(started) == 60 + 120 + 240 + 480)
        #expect(fixture.smtp.sessions.count == 1)
    }

    @Test("A problem trying again won't fix isn't retried")
    func permanentFailure() async throws {
        // Arrange
        fixture.smtp.change { $0.signInReply = SMTPReply(code: 535, lines: ["5.7.8 Rejected"]) }

        // Act
        let outcome = await fixture.api.emailDelivery.deliver(Self.message)

        // Assert
        #expect(outcome == .failed(.signInRefused))
        #expect(fixture.pauses.count < 1)
        #expect(fixture.smtp.sessions.count == 1)
    }

    @Test("It gives up once trying again would go past a day")
    func givesUp() async throws {
        // Arrange
        fixture.smtp.change { $0.connectFailures = Array(repeating: EmailSendFailure(.couldNotConnect), count: 100) }
        let started = fixture.signIn.clock.now

        // Act
        let outcome = await fixture.api.emailDelivery.deliver(Self.message)

        // Assert
        #expect(outcome == .gaveUp(.couldNotConnect))
        #expect(fixture.signIn.clock.now.timeIntervalSince(started) <= EmailDelivery.giveUpAfter)
        #expect(fixture.signIn.clock.now.timeIntervalSince(started) > EmailDelivery.giveUpAfter - EmailDelivery.longestDelay)
        #expect(fixture.smtp.sessions.isEmpty)
    }

    @Test("Each try reads the settings again, so a fix made meanwhile is used")
    func readsSettingsEachTry() async throws {
        // Arrange
        fixture.smtp.change { $0.connectFailures = [EmailSendFailure(.couldNotConnect)] }
        var settings = EmailRoutesTests.settings
        settings.recipients = ["three@example.net"]
        let changed = EmailSettingsChange(settings: settings, password: nil)
        let fixture = fixture
        fixture.pauses.onEach { _ in
            _ = try? fixture.api.email.change(changed, isConfirmed: false, by: fixture.signIn.device.id)
        }

        // Act
        let outcome = await fixture.api.emailDelivery.deliver(Self.message)

        // Assert
        #expect(outcome == .sent)
        #expect(fixture.smtp.sessions.first?.commands.contains { $0.line == "RCPT TO:<three@example.net>" } == true)
    }

    @Test("The system log says what happened without the password, the host or any address")
    func systemLogHoldsNoDetails() async throws {
        // Arrange
        let since = Date()
        fixture.smtp.change { $0.connectFailures = [EmailSendFailure(.couldNotConnect)] }

        // Act
        _ = await fixture.api.emailDelivery.deliver(Self.message)
        _ = try await fixture.send(.post, HiveEndpoint.testEmail)

        // Assert
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(at: store.position(date: since))
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == HiveLog.subsystem && $0.category == "Email" }
            .map(\.composedMessage)
        #expect(entries.contains { $0.hasPrefix("Couldn't send an email: couldNotConnect") })
        #expect(entries.contains { $0.hasPrefix("Sent an email to 2 recipients") })
        let details = [EmailRoutesTests.password, "smtp.example.com", "example.com", "example.org", "Test Hive"]
        for entry in entries {
            for detail in details {
                #expect(!entry.contains(detail), "\(entry)")
            }
        }
    }
}
