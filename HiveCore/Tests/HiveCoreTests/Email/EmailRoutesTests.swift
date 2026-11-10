import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

struct EmailRoutesTests {
    static let password = "s3cret-Smtp-Password-Never-Shown"

    static let settings = EmailSettings(
        host: "smtp.example.com",
        port: 587,
        security: .startTLS,
        username: "hive@example.com",
        senderAddress: "hive@example.com",
        recipients: ["one@example.com", "two@example.org"]
    )

    private let fixture: APIFixture

    init() throws {
        fixture = try APIFixture()
    }

    private func setUp(_ settings: EmailSettings = settings, password: String? = password) async throws -> APIAnswer {
        try await fixture.send(.put, HiveEndpoint.email, json: EmailSettingsChange(settings: settings, password: password))
    }

    private func storedPassword() throws -> String? {
        let sealed = try fixture.signIn.database.writer.read { database in
            try Data.fetchOne(database, sql: "SELECT sealedPassword FROM emailSettings")
        }
        return try sealed.flatMap { String(bytes: try fixture.sealer.open(SealedSecret(data: $0)), encoding: .utf8) }
    }

    @Test("Email starts off, and setting it up stores the settings, seals the password and records both")
    func setsUp() async throws {
        // Arrange
        let before = try await fixture.send(.get, HiveEndpoint.email).decoded(as: EmailSettingsState.self)
        var requested = Self.settings
        requested.host = " SMTP.Example.com "
        requested.recipients = [" one@example.com", "two@example.org "]

        // Act
        let answer = try await setUp(requested)

        // Assert
        #expect(before == EmailSettingsState(settings: nil, hasPassword: false))
        #expect(answer.status == .ok)
        #expect(try answer.decoded(as: EmailSettingsState.self) == EmailSettingsState(settings: Self.settings, hasPassword: true))
        #expect(try storedPassword() == Self.password)
        #expect(try Array(fixture.auditEvents().prefix(2)) == [.email(.passwordEntered), .email(.setUp(Self.settings))])
    }

    @Test("Changing anything but the host keeps the password and needs no confirmation")
    func keepsPassword() async throws {
        // Arrange
        _ = try await setUp()
        var changed = Self.settings
        changed.port = 465
        changed.security = .implicitTLS
        changed.recipients = ["three@example.net"]

        // Act
        let answer = try await setUp(changed, password: nil)

        // Assert
        #expect(answer.status == .ok)
        #expect(try answer.decoded(as: EmailSettingsState.self).hasPassword)
        #expect(try storedPassword() == Self.password)
        #expect(try fixture.auditEvents().first == .email(.changed(old: Self.settings, new: changed)))
    }

    @Test("Changing the host needs confirming, and without it nothing changes")
    func hostChangeNeedsConfirmation() async throws {
        // Arrange
        _ = try await setUp()
        let before = try fixture.auditEvents()
        var moved = Self.settings
        moved.host = "smtp.elsewhere.example"

        // Act
        let answer = try await setUp(moved, password: "\(Self.password)-2")

        // Assert
        #expect(answer.status == .preconditionRequired)
        #expect(try answer.confirmationReasons == [.emailHostChanged])
        #expect(try fixture.auditEvents() == before)
        #expect(try storedPassword() == Self.password)
    }

    @Test("Changing the host clears the password, so it's never sent to the new host without being entered again")
    func hostChangeClearsPassword() async throws {
        // Arrange
        _ = try await setUp()
        var moved = Self.settings
        moved.host = "smtp.elsewhere.example"
        moved.username = ""

        // Act
        let answer = try await fixture.sendConfirmed(.put, HiveEndpoint.email, json: EmailSettingsChange(settings: moved, password: nil))
        let test = try await fixture.send(.post, HiveEndpoint.testEmail).decoded(as: TestEmailOutcome.self)

        // Assert
        #expect(answer.status == .ok)
        #expect(try answer.decoded(as: EmailSettingsState.self).hasPassword == false)
        #expect(try storedPassword() == nil)
        #expect(test == .sent)
        #expect(fixture.smtp.sessions.last?.server.host == "smtp.elsewhere.example")
        #expect(fixture.smtp.sessions.last?.commands.contains { $0.line.hasPrefix("AUTH") } == false)
    }

    @Test("A new password entered with a new host is kept")
    func hostChangeWithPassword() async throws {
        // Arrange
        _ = try await setUp()
        var moved = Self.settings
        moved.host = "smtp.elsewhere.example"
        let change = EmailSettingsChange(settings: moved, password: "\(Self.password)-2")

        // Act
        let answer = try await fixture.sendConfirmed(.put, HiveEndpoint.email, json: change)

        // Assert
        #expect(answer.status == .ok)
        #expect(try storedPassword() == "\(Self.password)-2")
        #expect(try Array(fixture.auditEvents().prefix(2)) == [
            .email(.passwordEntered), .email(.changed(old: Self.settings, new: moved)),
        ])
    }

    @Test("A username needs a password, including when a new host has cleared the old one")
    func usernameNeedsPassword() async throws {
        // Arrange
        _ = try await setUp()
        var moved = Self.settings
        moved.host = "smtp.elsewhere.example"

        // Act
        let first = try await APIFixture().send(.put, HiveEndpoint.email, json: EmailSettingsChange(settings: Self.settings, password: nil))
        let afterMove = try await fixture.sendConfirmed(.put, HiveEndpoint.email, json: EmailSettingsChange(settings: moved, password: nil))

        // Assert
        #expect(first.status == .unprocessableContent)
        #expect(try first.problems == [ConfigurationProblem(field: .password, reason: .missing)])
        #expect(afterMove.status == .unprocessableContent)
        #expect(try storedPassword() == Self.password)
    }

    @Test("Settings that could break out of an SMTP command or a header, or fail TLS's check, are refused")
    func refusesBadSettings() async throws {
        // Arrange
        let before = try fixture.auditEvents()
        let bad = EmailSettings(
            host: "192.168.1.10",
            port: 0,
            security: .startTLS,
            username: "hive\r\nRCPT TO:<x@example.net>",
            senderAddress: "hive@example.com>\r\nBcc: x@example.net",
            recipients: ["one@example.com", "ONE@example.com", "not an address", "<x@example.net>"]
        )

        // Act
        let answer = try await setUp(bad, password: "pass\0word")
        let noRecipients = try await setUp(EmailSettings(
            host: "smtp.example.com",
            port: 587,
            security: .startTLS,
            username: "",
            senderAddress: "hive@example.com",
            recipients: []
        ))

        // Assert
        #expect(answer.status == .unprocessableContent)
        #expect(try Set(answer.problems) == [
            ConfigurationProblem(field: .host, reason: .invalid),
            ConfigurationProblem(field: .port, reason: .outOfRange),
            ConfigurationProblem(field: .user, reason: .invalid),
            ConfigurationProblem(field: .password, reason: .invalid),
            ConfigurationProblem(field: .senderAddress, reason: .invalid),
            ConfigurationProblem(field: .recipient, index: 1, reason: .duplicate),
            ConfigurationProblem(field: .recipient, index: 2, reason: .invalid),
            ConfigurationProblem(field: .recipient, index: 3, reason: .invalid),
        ])
        #expect(try noRecipients.problems == [ConfigurationProblem(field: .recipients, reason: .missing)])
        #expect(try fixture.auditEvents() == before)
    }

    @Test("Turning email off clears the settings and the password")
    func turnsOff() async throws {
        // Arrange
        _ = try await setUp()

        // Act
        let answer = try await fixture.send(.delete, HiveEndpoint.email)
        let again = try await fixture.send(.delete, HiveEndpoint.email)
        let test = try await fixture.send(.post, HiveEndpoint.testEmail).decoded(as: TestEmailOutcome.self)
        let state = try await fixture.send(.get, HiveEndpoint.email).decoded(as: EmailSettingsState.self)

        // Assert
        #expect(answer.status == .noContent)
        #expect(again.status == .notFound)
        #expect(state == EmailSettingsState(settings: nil, hasPassword: false))
        #expect(try !fixture.everyStoredValue().contains { $0.table == "emailSettings" })
        #expect(try fixture.auditEvents().first == .email(.turnedOff))
        #expect(test == .failed(.notSetUp, serverReply: nil))
    }

    @Test("A test email goes to every recipient, from the Hive, signed in with the password")
    func sendsTestEmail() async throws {
        // Arrange
        _ = try await setUp()

        // Act
        let answer = try await fixture.send(.post, HiveEndpoint.testEmail)

        // Assert
        #expect(answer.status == .ok)
        #expect(try answer.decoded(as: TestEmailOutcome.self) == .sent)
        let session = try #require(fixture.smtp.sessions.first)
        #expect(session.server == SMTPServer(host: "smtp.example.com", port: 587, security: .startTLS))
        let token = Data("\0hive@example.com\0\(Self.password)".utf8).base64EncodedString()
        #expect(session.commands.contains { $0.line == "AUTH PLAIN \(token)" && $0.isSecure })
        #expect(session.commands.filter { $0.line.hasPrefix("RCPT") }.map(\.line) == [
            "RCPT TO:<one@example.com>", "RCPT TO:<two@example.org>",
        ])
        let message = try ParsedMessage(try #require(session.message))
        #expect(message.header("From") == "\"Test Hive\" <hive@example.com>")
        #expect(try message.decodedHeader("Subject") == "Test email from “Test Hive”")
    }

    @Test("A test email that fails says why, with the server's answer")
    func testEmailFails() async throws {
        // Arrange
        _ = try await setUp()
        fixture.smtp.change { $0.signInReply = SMTPReply(code: 535, lines: ["5.7.8 Username and Password not accepted"]) }

        // Act
        let outcome = try await fixture.send(.post, HiveEndpoint.testEmail).decoded(as: TestEmailOutcome.self)

        // Assert
        #expect(outcome == .failed(.signInRefused, serverReply: "535 5.7.8 Username and Password not accepted"))
        #expect(fixture.smtp.sessions.count == 1)
    }

    @Test("A test email is tried once, even when the provider can't be reached")
    func testEmailNotRetried() async throws {
        // Arrange
        _ = try await setUp()
        fixture.smtp.change { $0.connectFailures = [EmailSendFailure(.couldNotConnect)] }

        // Act
        let outcome = try await fixture.send(.post, HiveEndpoint.testEmail).decoded(as: TestEmailOutcome.self)

        // Assert
        #expect(outcome == .failed(.couldNotConnect, serverReply: nil))
        #expect(fixture.smtp.sessions.isEmpty)
        #expect(fixture.pauses.count < 1)
    }

    @Test("No answer, audit entry or stored value holds the password, including refusals")
    func passwordNeverShown() async throws {
        // Arrange
        var answers: [APIAnswer] = []
        var moved = Self.settings
        moved.host = "smtp.elsewhere.example"
        var refused = Self.settings
        refused.senderAddress = ""

        // Act
        answers.append(try await setUp())
        answers.append(try await setUp(refused, password: Self.password))
        answers.append(try await setUp(Self.settings, password: "\(Self.password)\n"))
        answers.append(try await setUp(moved, password: Self.password))
        answers.append(try await fixture.send(.get, HiveEndpoint.email))
        answers.append(try await fixture.send(.post, HiveEndpoint.testEmail))
        answers.append(try await fixture.send(.get, HiveEndpoint.auditLog))

        // Assert
        #expect(answers.map(\.status) == [.ok, .unprocessableContent, .unprocessableContent, .preconditionRequired, .ok, .ok, .ok])
        for answer in answers {
            #expect(answer.body.range(of: Data(Self.password.utf8)) == nil)
        }
        for (table, value) in try fixture.everyStoredValue() {
            #expect(value.range(of: Data(Self.password.utf8)) == nil, "\(table)")
        }
        let printed = String(describing: EmailSettingsChange(settings: Self.settings, password: Self.password))
        #expect(!printed.contains(Self.password))
    }
}
