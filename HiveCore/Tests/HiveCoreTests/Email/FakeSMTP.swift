import Foundation
@testable import HiveCore
import HiveKit
import Synchronization

/// Stands in for mail servers: answers each connection as a provider would, as told, and records
/// what Hive sent, so no test opens a connection.
final class FakeSMTP: SMTPConnecting {
    struct Behavior: Sendable {
        /// Each connection fails with the first of these, which is then used up.
        var connectFailures: [EmailSendFailure] = []
        var offersStartTLS = true
        var signInMechanisms = "PLAIN LOGIN"
        var signInReply = SMTPReply(code: 235, lines: ["2.7.0 Accepted"])
        var recipientReply = SMTPReply(code: 250, lines: ["2.1.5 OK"])
    }

    /// What one connection saw.
    struct Session: Sendable {
        let server: SMTPServer
        /// Each command line, and whether TLS was up when it was sent.
        var commands: [(line: String, isSecure: Bool)] = []
        /// The message as it was sent after `DATA`, dot-stuffed, without the line ending it.
        var message: Data?
    }

    private struct State {
        var behavior = Behavior()
        var sessions: [Session] = []
    }

    private let state = Mutex(State())

    var sessions: [Session] {
        state.withLock { $0.sessions }
    }

    func change(_ change: (inout Behavior) -> Void) {
        state.withLock { change(&$0.behavior) }
    }

    func withConnection<Result: Sendable>(
        to server: SMTPServer,
        _ body: (any SMTPTransport) async throws -> Result
    ) async throws -> Result {
        let behavior = try state.withLock { state in
            if !state.behavior.connectFailures.isEmpty {
                throw state.behavior.connectFailures.removeFirst()
            }
            state.sessions.append(Session(server: server))
            return state.behavior
        }
        let transport = FakeSMTPTransport(behavior: behavior, isSecure: server.security == .implicitTLS)
        defer {
            state.withLock { state in
                state.sessions[state.sessions.count - 1].commands = transport.commands
                state.sessions[state.sessions.count - 1].message = transport.message
            }
        }
        return try await body(transport)
    }
}

private final class FakeSMTPTransport: SMTPTransport {
    let behavior: FakeSMTP.Behavior
    private(set) var isSecure: Bool
    private(set) var commands: [(line: String, isSecure: Bool)] = []
    private(set) var message: Data?
    private var replies: [SMTPReply] = [SMTPReply(code: 220, lines: ["fake.example.com ESMTP"])]
    private var dataBuffer: [UInt8]?
    private var loginStep: Int?

    init(behavior: FakeSMTP.Behavior, isSecure: Bool) {
        self.behavior = behavior
        self.isSecure = isSecure
    }

    func reply() async throws -> SMTPReply {
        guard !replies.isEmpty else { throw EmailSendFailure(.connectionClosed) }
        return replies.removeFirst()
    }

    func send(_ bytes: [UInt8]) async throws {
        if var buffer = dataBuffer {
            buffer.append(contentsOf: bytes)
            let end = Array("\r\n.\r\n".utf8)
            if buffer.count >= end.count, Array(buffer.suffix(end.count)) == end {
                message = Data(buffer.dropLast(3))
                dataBuffer = nil
                replies.append(SMTPReply(code: 250, lines: ["2.0.0 Queued"]))
            } else {
                dataBuffer = buffer
            }
            return
        }
        let line = (String(bytes: bytes, encoding: .utf8) ?? "").replacingOccurrences(of: "\r\n", with: "")
        commands.append((line, isSecure))
        replies.append(answer(to: line))
    }

    func startTLS() async throws {
        isSecure = true
    }

    private func answer(to line: String) -> SMTPReply {
        if let step = loginStep {
            loginStep = step == 0 ? 1 : nil
            return step == 0 ? SMTPReply(code: 334, lines: ["UGFzc3dvcmQ6"]) : behavior.signInReply
        }
        let verb = line.split(separator: " ").first.map { $0.uppercased() } ?? ""
        switch verb {
        case "EHLO":
            return hello()
        case "STARTTLS":
            return SMTPReply(code: 220, lines: ["2.0.0 Ready to start TLS"])
        case "AUTH" where line.uppercased() == "AUTH LOGIN":
            loginStep = 0
            return SMTPReply(code: 334, lines: ["VXNlcm5hbWU6"])
        case "AUTH":
            return behavior.signInReply
        case "MAIL":
            return SMTPReply(code: 250, lines: ["2.1.0 OK"])
        case "RCPT":
            return behavior.recipientReply
        case "DATA":
            dataBuffer = []
            return SMTPReply(code: 354, lines: ["Go ahead"])
        case "QUIT":
            return SMTPReply(code: 221, lines: ["Bye"])
        default:
            return SMTPReply(code: 500, lines: ["Unrecognized command"])
        }
    }

    private func hello() -> SMTPReply {
        var lines = ["fake.example.com"]
        if behavior.offersStartTLS, !isSecure { lines.append("STARTTLS") }
        if !behavior.signInMechanisms.isEmpty { lines.append("AUTH \(behavior.signInMechanisms)") }
        lines.append("8BITMIME")
        return SMTPReply(code: 250, lines: lines)
    }
}
