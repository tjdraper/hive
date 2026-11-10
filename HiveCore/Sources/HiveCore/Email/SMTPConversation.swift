import Foundation
import HiveKit

/// Where a message goes to be sent.
struct SMTPServer: Equatable, Sendable {
    let host: String
    let port: Int
    let security: EmailSecurity
}

struct SMTPCredentials: Sendable {
    let username: String
    let password: String
}

/// One open connection to a mail server.
protocol SMTPTransport {
    /// Throws `EmailSendFailure` when the connection fails, closes or goes quiet.
    func reply() async throws -> SMTPReply
    func send(_ bytes: [UInt8]) async throws
    /// Starts TLS on the connection, checking the server's certificate against its host name.
    func startTLS() async throws
}

/// Opens connections to mail servers. The real one is `NIOSMTPConnector`, and tests stand in for it.
protocol SMTPConnecting: Sendable {
    /// Closes the connection once `body` returns or throws.
    func withConnection<Result: Sendable>(
        to server: SMTPServer,
        _ body: (any SMTPTransport) async throws -> Result
    ) async throws -> Result
}

/// Why a message wasn't sent.
struct EmailSendFailure: Error, Equatable {
    let problem: EmailProblem
    /// What the server answered, when the problem is something it said.
    let reply: SMTPReply?

    init(_ problem: EmailProblem, reply: SMTPReply? = nil) {
        self.problem = problem
        self.reply = reply
    }

    /// Whether trying again later might work: the provider was unreachable, or answered "not now".
    var isTransient: Bool {
        switch problem {
        case .couldNotConnect, .timedOut, .connectionClosed: true
        default: reply?.isTransient ?? false
        }
    }
}

/// Sends one message over a connection (RFC 5321): greeting, `EHLO`, TLS, signing in, the envelope and
/// the message. Nothing, the username and password included, is sent before TLS is up.
struct SMTPConversation {
    /// An address literal rather than the Mac's name, which would tell the provider more than it needs.
    static let clientName = "[127.0.0.1]"

    let transport: any SMTPTransport
    let security: EmailSecurity
    let credentials: SMTPCredentials?

    func send(_ message: Data, from sender: String, to recipients: [String]) async throws {
        try await expect(transport.reply(), [220], else: .unexpectedReply)
        var extensions = try await hello()
        if security == .startTLS {
            guard extensions.contains(where: { $0.uppercased() == "STARTTLS" }) else { throw EmailSendFailure(.startTLSUnavailable) }
            try await command("STARTTLS", expecting: [220], else: .startTLSUnavailable)
            try await transport.startTLS()
            // What the server offers before TLS can't be trusted, so it's asked again.
            extensions = try await hello()
        }
        if let credentials {
            try await signIn(credentials, mechanisms: Self.signInMechanisms(in: extensions))
        }

        try await command("MAIL FROM:<\(sender)>", expecting: [250], else: .senderRefused)
        for recipient in recipients {
            try await command("RCPT TO:<\(recipient)>", expecting: [250, 251], else: .recipientRefused)
        }
        try await command("DATA", expecting: [354], else: .messageRefused)
        try await transport.send(Self.dotStuffed(message) + Array(".\r\n".utf8))
        try await expect(transport.reply(), [250], else: .messageRefused)
        // The message is sent. A server that doesn't answer `QUIT` properly changes nothing.
        try? await transport.send(Array("QUIT\r\n".utf8))
    }

    /// The server's extensions, one per line after its name.
    private func hello() async throws -> [String] {
        try await transport.send(Array("EHLO \(Self.clientName)\r\n".utf8))
        return try await Array(expect(transport.reply(), [250], else: .unexpectedReply).lines.dropFirst())
    }

    /// `PLAIN` when the server offers it, as every major provider does, and `LOGIN` otherwise.
    private func signIn(_ credentials: SMTPCredentials, mechanisms: Set<String>) async throws {
        if mechanisms.contains("PLAIN") {
            let token = Data(("\0" + credentials.username + "\0" + credentials.password).utf8).base64EncodedString()
            try await command("AUTH PLAIN \(token)", expecting: [235], else: .signInRefused)
        } else if mechanisms.contains("LOGIN") {
            try await command("AUTH LOGIN", expecting: [334], else: .signInRefused)
            try await command(Data(credentials.username.utf8).base64EncodedString(), expecting: [334], else: .signInRefused)
            try await command(Data(credentials.password.utf8).base64EncodedString(), expecting: [235], else: .signInRefused)
        } else {
            throw EmailSendFailure(.signInUnavailable)
        }
    }

    @discardableResult
    private func command(_ line: String, expecting codes: Set<Int>, else problem: EmailProblem) async throws -> SMTPReply {
        try await transport.send(Array((line + "\r\n").utf8))
        return try await expect(transport.reply(), codes, else: problem)
    }

    @discardableResult
    private func expect(_ reply: SMTPReply, _ codes: Set<Int>, else problem: EmailProblem) throws -> SMTPReply {
        guard codes.contains(reply.code) else { throw EmailSendFailure(problem, reply: reply) }
        return reply
    }

    /// From `AUTH PLAIN LOGIN`, or the older `AUTH=PLAIN LOGIN` some servers still send.
    static func signInMechanisms(in extensions: [String]) -> Set<String> {
        var mechanisms: Set<String> = []
        for line in extensions {
            let words = line.uppercased().split(whereSeparator: { $0 == " " || $0 == "=" })
            guard words.first == "AUTH" else { continue }
            mechanisms.formUnion(words.dropFirst().map(String.init))
        }
        return mechanisms
    }

    /// A line of the message starting with `.` gets another, so the server doesn't read it as the end
    /// (RFC 5321 §4.5.2). `message` ends with CRLF.
    static func dotStuffed(_ message: Data) -> [UInt8] {
        var stuffed: [UInt8] = []
        stuffed.reserveCapacity(message.count + 16)
        var isLineStart = true
        for byte in message {
            if isLineStart, byte == UInt8(ascii: ".") { stuffed.append(byte) }
            stuffed.append(byte)
            isLineStart = byte == UInt8(ascii: "\n")
        }
        return stuffed
    }
}
