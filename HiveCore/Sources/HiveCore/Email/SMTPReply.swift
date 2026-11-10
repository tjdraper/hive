import Foundation

/// One reply from a mail server, its lines joined.
struct SMTPReply: Equatable, Sendable {
    let code: Int
    /// Each line's text after the code, so `EHLO`'s lists the server's extensions.
    let lines: [String]

    var isPositive: Bool {
        (200 ..< 400).contains(code)
    }

    /// A 4xx: the server may take it later.
    var isTransient: Bool {
        (400 ..< 500).contains(code)
    }

    var text: String {
        "\(code) \(lines.joined(separator: " "))"
    }
}

enum SMTPReplyError: Error, Equatable {
    case malformed
    case tooLong
}

/// Gathers the bytes a server sends into replies: lines ending CRLF, each starting with the same three
/// digits, followed by `-` on every line but the last (RFC 5321 §4.2).
struct SMTPReplyReader {
    /// RFC 5321 allows 512 bytes a line. Some servers send longer ones, but not this long.
    static let longestLine = 4096
    /// A reply that never ends is a server Hive shouldn't wait on.
    static let mostLines = 100

    private var buffer: [UInt8] = []
    private var pendingCode: Int?
    private var pendingLines: [String] = []

    /// True when nothing has arrived beyond the replies already read.
    var isEmpty: Bool {
        buffer.isEmpty && pendingLines.isEmpty
    }

    mutating func append(_ bytes: some Sequence<UInt8>) {
        buffer.append(contentsOf: bytes)
    }

    /// The next whole reply, or nil until more bytes arrive.
    mutating func next() throws -> SMTPReply? {
        while let lineEnd = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            var line = Array(buffer[..<lineEnd])
            buffer.removeSubrange(...lineEnd)
            if line.last == UInt8(ascii: "\r") { line.removeLast() }
            if let reply = try take(line) { return reply }
        }
        if buffer.count > Self.longestLine { throw SMTPReplyError.tooLong }
        return nil
    }

    private mutating func take(_ line: [UInt8]) throws -> SMTPReply? {
        guard line.count >= 3, line.count <= Self.longestLine,
              let code = String(bytes: line.prefix(3), encoding: .ascii).flatMap({ Int($0) }), (200 ..< 600).contains(code)
        else { throw SMTPReplyError.malformed }
        let separator = line.count > 3 ? line[3] : UInt8(ascii: " ")
        guard separator == UInt8(ascii: " ") || separator == UInt8(ascii: "-") else { throw SMTPReplyError.malformed }
        if let pendingCode, pendingCode != code { throw SMTPReplyError.malformed }

        pendingCode = code
        let text = line.dropFirst(4)
        // Servers write in ASCII, or UTF-8 with `SMTPUTF8`. Latin 1 reads any other bytes as something.
        pendingLines.append(String(bytes: text, encoding: .utf8) ?? String(bytes: text, encoding: .isoLatin1) ?? "")
        guard pendingLines.count <= Self.mostLines else { throw SMTPReplyError.tooLong }
        guard separator == UInt8(ascii: " ") else { return nil }

        let reply = SMTPReply(code: code, lines: pendingLines)
        pendingCode = nil
        pendingLines = []
        return reply
    }
}
