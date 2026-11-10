import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct SMTPConversationTests {
    private static let credentials = SMTPCredentials(username: "hive@example.com", password: "app-password")
    private static let message = Data("Subject: Hi\r\n\r\n.Body\r\n".utf8)

    private func send(
        _ smtp: FakeSMTP,
        security: EmailSecurity = .startTLS,
        credentials: SMTPCredentials? = credentials
    ) async throws {
        let server = SMTPServer(host: "smtp.example.com", port: security.defaultPort, security: security)
        try await smtp.withConnection(to: server) { transport in
            try await SMTPConversation(transport: transport, security: security, credentials: credentials)
                .send(Self.message, from: "hive@example.com", to: ["one@example.com", "two@example.org"])
        }
    }

    @Test("With STARTTLS, nothing but EHLO and STARTTLS is sent before TLS, and EHLO is asked again after")
    func startTLSFirst() async throws {
        // Arrange
        let smtp = FakeSMTP()

        // Act
        try await send(smtp)

        // Assert
        let commands = try #require(smtp.sessions.first).commands
        #expect(commands.filter { !$0.isSecure }.map(\.line) == ["EHLO [127.0.0.1]", "STARTTLS"])
        #expect(commands.filter(\.isSecure).map { $0.line.split(separator: " ").first.map(String.init) ?? "" } == [
            "EHLO", "AUTH", "MAIL", "RCPT", "RCPT", "DATA", "QUIT",
        ])
        let token = Data("\0hive@example.com\0app-password".utf8).base64EncodedString()
        #expect(commands.contains { $0.line == "AUTH PLAIN \(token)" })
        #expect(commands.contains { $0.line == "MAIL FROM:<hive@example.com>" })
        #expect(commands.contains { $0.line == "RCPT TO:<two@example.org>" })
        #expect(smtp.sessions.first?.message == Data("Subject: Hi\r\n\r\n..Body\r\n".utf8))
    }

    @Test("A server that doesn't offer STARTTLS is sent nothing more, the password least of all")
    func refusesWithoutStartTLS() async throws {
        // Arrange
        let smtp = FakeSMTP()
        smtp.change { $0.offersStartTLS = false }

        // Act
        let failure = await #expect(throws: EmailSendFailure.self) { try await send(smtp) }

        // Assert
        #expect(failure?.problem == .startTLSUnavailable)
        #expect(failure?.isTransient == false)
        #expect(smtp.sessions.first?.commands.map(\.line) == ["EHLO [127.0.0.1]"])
    }

    @Test("With implicit TLS, everything is sent over TLS")
    func implicitTLS() async throws {
        // Arrange
        let smtp = FakeSMTP()

        // Act
        try await send(smtp, security: .implicitTLS)

        // Assert
        let commands = try #require(smtp.sessions.first).commands
        let isAllSecure = commands.allSatisfy(\.isSecure)
        #expect(isAllSecure)
        #expect(!commands.contains { $0.line == "STARTTLS" })
    }

    @Test("LOGIN is used when the server doesn't offer PLAIN")
    func login() async throws {
        // Arrange
        let smtp = FakeSMTP()
        smtp.change { $0.signInMechanisms = "LOGIN" }

        // Act
        try await send(smtp)

        // Assert
        let lines = try #require(smtp.sessions.first).commands.map(\.line)
        #expect(lines.contains("AUTH LOGIN"))
        #expect(lines.contains(Data("hive@example.com".utf8).base64EncodedString()))
        #expect(lines.contains(Data("app-password".utf8).base64EncodedString()))
    }

    @Test("No credentials are sent when there's no username, or when the server offers no way to sign in")
    func signInMechanisms() async throws {
        // Arrange
        let withoutUsername = FakeSMTP()
        let withoutMechanism = FakeSMTP()
        withoutMechanism.change { $0.signInMechanisms = "CRAM-MD5" }

        // Act
        try await send(withoutUsername, credentials: nil)
        let failure = await #expect(throws: EmailSendFailure.self) { try await send(withoutMechanism) }

        // Assert
        #expect(withoutUsername.sessions.first?.commands.contains { $0.line.hasPrefix("AUTH") } == false)
        #expect(failure?.problem == .signInUnavailable)
        #expect(withoutMechanism.sessions.first?.commands.contains { $0.line.hasPrefix("AUTH") } == false)
    }

    @Test("A refused password stops the send, and only a 4xx answer is worth trying again")
    func signInRefused() async throws {
        // Arrange
        let refused = FakeSMTP()
        refused.change { $0.signInReply = SMTPReply(code: 535, lines: ["5.7.8 Username and Password not accepted"]) }
        let busy = FakeSMTP()
        busy.change { $0.signInReply = SMTPReply(code: 454, lines: ["4.7.0 Try again later"]) }

        // Act
        let refusal = await #expect(throws: EmailSendFailure.self) { try await send(refused) }
        let notNow = await #expect(throws: EmailSendFailure.self) { try await send(busy) }

        // Assert
        #expect(refusal?.problem == .signInRefused)
        #expect(refusal?.reply?.text == "535 5.7.8 Username and Password not accepted")
        #expect(refusal?.isTransient == false)
        #expect(notNow?.isTransient == true)
        #expect(refused.sessions.first?.commands.contains { $0.line.hasPrefix("MAIL") } == false)
    }

    @Test("A refused recipient stops the send before the message")
    func recipientRefused() async throws {
        // Arrange
        let smtp = FakeSMTP()
        smtp.change { $0.recipientReply = SMTPReply(code: 550, lines: ["5.1.1 No such user"]) }

        // Act
        let failure = await #expect(throws: EmailSendFailure.self) { try await send(smtp) }

        // Assert
        #expect(failure?.problem == .recipientRefused)
        #expect(smtp.sessions.first?.message == nil)
    }

    @Test("Sign-in mechanisms are read from both forms of the AUTH line")
    func mechanismsParsed() {
        // Act
        let modern = SMTPConversation.signInMechanisms(in: ["SIZE 35882577", "AUTH LOGIN PLAIN XOAUTH2"])
        let older = SMTPConversation.signInMechanisms(in: ["AUTH=LOGIN"])

        // Assert
        #expect(modern == ["LOGIN", "PLAIN", "XOAUTH2"])
        #expect(older == ["LOGIN"])
    }
}

struct SMTPReplyReaderTests {
    @Test("A reply split across reads, and one of several lines, are read whole")
    func multiLine() throws {
        // Arrange
        var reader = SMTPReplyReader()
        var replies: [SMTPReply] = []

        // Act
        for chunk in ["220 smtp.example.com ES", "MTP\r\n250-smtp.example.com\r\n250-STARTTLS\r", "\n250 AUTH PLAIN\r\n"] {
            reader.append(Array(chunk.utf8))
            while let reply = try reader.next() { replies.append(reply) }
        }

        // Assert
        #expect(replies == [
            SMTPReply(code: 220, lines: ["smtp.example.com ESMTP"]),
            SMTPReply(code: 250, lines: ["smtp.example.com", "STARTTLS", "AUTH PLAIN"]),
        ])
        #expect(reader.isEmpty)
    }

    @Test("Something that isn't an SMTP reply is refused")
    func malformed() {
        for text in ["hello\r\n", "250-one\r\n251 two\r\n", "250+x\r\n", "99 x\r\n", String(repeating: "2", count: 5000)] {
            // Arrange
            var reader = SMTPReplyReader()
            reader.append(Array(text.utf8))
            var replies: [SMTPReply] = []

            // Act, Assert
            #expect(throws: SMTPReplyError.self) {
                while let reply = try reader.next() { replies.append(reply) }
            }
        }
    }

    @Test("Bytes after the last reply are noticed")
    func leftover() throws {
        // Arrange
        var reader = SMTPReplyReader()
        reader.append(Array("220 Ready to start TLS\r\n250 injected\r\n".utf8))

        // Act
        _ = try reader.next()

        // Assert
        #expect(!reader.isEmpty)
    }
}
