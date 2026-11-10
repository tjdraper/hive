import Foundation
@testable import HiveCore
import Testing

struct EmailMessageTests {
    private static let builder = builder(senderName: "Hive")

    private static func builder(senderName: String) -> EmailMessageBuilder {
        EmailMessageBuilder(
            senderName: senderName,
            senderAddress: "hive@example.com",
            recipients: ["one@example.com", "two@example.org"],
            date: Date(timeIntervalSince1970: 1_794_000_000),
            timeZone: TimeZone(identifier: "America/Chicago") ?? .gmt,
            messageID: UUID()
        )
    }

    @Test("Every line is ASCII, ends in CRLF and is short enough for any server")
    func linesAreValid() throws {
        // Arrange
        let builder = Self.builder(senderName: "Ruche « Bureau » 🐝")
        let message = EmailMessage(
            subject: "Sauvegarde échouée pour “Café Ünïcode” 🐝, et encore un peu de texte pour plier la ligne",
            body: String(repeating: "Ligne très longue avec des accents et des abeilles 🐝. ", count: 20) + "\nFin."
        )

        // Act
        let built = builder.build(message)

        // Assert
        #expect(built.allSatisfy { $0 < 0x80 })
        let text = try #require(String(bytes: built, encoding: .ascii))
        #expect(text.hasSuffix("\r\n"))
        #expect(!text.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        #expect(!text.replacingOccurrences(of: "\r\n", with: "").contains("\r"))
        for line in text.components(separatedBy: "\r\n") {
            #expect(line.count <= EmailMessageBuilder.lineLength + 20, "\(line)")
        }
    }

    @Test("Non-ASCII names, subjects and bodies read back as they were written")
    func nonASCIIRoundTrips() throws {
        // Arrange
        let builder = Self.builder(senderName: "Ruche « Bureau » 🐝")
        let subject = "Sauvegarde échouée pour “Café Ünïcode” 🐝, et encore un peu de texte pour plier la ligne"
        let body = "Bonjour,\nLa sauvegarde de « Café » a échoué. 🐝\n\nÀ bientôt"

        // Act
        let parsed = try ParsedMessage(builder.build(EmailMessage(subject: subject, body: body)))

        // Assert
        #expect(try parsed.decodedHeader("Subject") == subject)
        #expect(try parsed.decodedHeader("From") == "Ruche « Bureau » 🐝 <hive@example.com>")
        #expect(parsed.header("Content-Type") == "text/plain; charset=utf-8")
        #expect(parsed.header("Content-Transfer-Encoding") == "base64")
        #expect(parsed.header("MIME-Version") == "1.0")
        #expect(try parsed.decodedBody() == body.replacingOccurrences(of: "\n", with: "\r\n"))
    }

    @Test("A plain subject and name stay readable, and a long subject is folded at spaces")
    func plainHeaders() throws {
        // Arrange
        let subject = "Backup failed: “site” on “web-1” could not reach the server after several tries".replacingOccurrences(
            of: "“",
            with: "\""
        ).replacingOccurrences(of: "”", with: "\"")

        // Act
        let parsed = try ParsedMessage(Self.builder.build(EmailMessage(subject: subject, body: "Body")))

        // Assert
        #expect(parsed.header("Subject") == subject)
        #expect(parsed.rawHeader("Subject")?.contains("\r\n ") == true)
        #expect(parsed.header("From") == "\"Hive\" <hive@example.com>")
        #expect(parsed.header("To") == "one@example.com, two@example.org")
        #expect(parsed.header("Date") == "Fri, 6 Nov 2026 15:20:00 -0600")
        #expect(parsed.header("Message-ID")?.hasSuffix("@example.com>") == true)
    }

    @Test("A line break in a subject can't add a header, and text that looks encoded is encoded")
    func noHeaderInjection() throws {
        // Arrange
        let subjects = ["Failed\r\nBcc: someone@example.net", "Failed\nBcc: someone@example.net", "=?utf-8?B?SGk=?="]

        for subject in subjects {
            // Act
            let parsed = try ParsedMessage(Self.builder.build(EmailMessage(subject: subject, body: "Body")))

            // Assert
            #expect(parsed.header("Bcc") == nil)
            #expect(try parsed.decodedHeader("Subject") == subject)
        }
    }

    @Test("A name with quotes is encoded rather than breaking out of its quotes")
    func quotedName() throws {
        // Arrange
        let builder = Self.builder(senderName: "The \"Main\" Hive")

        // Act
        let parsed = try ParsedMessage(builder.build(EmailMessage(subject: "Hi", body: "Body")))

        // Assert
        #expect(try parsed.decodedHeader("From") == "The \"Main\" Hive <hive@example.com>")
    }

    @Test("A message line starting with a dot gets another, so it doesn't end the message")
    func dotStuffing() {
        // Arrange
        let message = Data(".start\r\nmiddle\r\n.\r\n..two\r\nend.\r\n".utf8)

        // Act
        let stuffed = SMTPConversation.dotStuffed(message)

        // Assert
        #expect(String(bytes: stuffed, encoding: .ascii) == "..start\r\nmiddle\r\n..\r\n...two\r\nend.\r\n")
    }
}

/// A built message read back as a mail app would: headers unfolded, encoded words and the body decoded.
struct ParsedMessage {
    enum ParseError: Error {
        case notASCIIOrNoBlankLine
        case badEncodedWord(String)
        case badBody
    }

    let headers: [(name: String, raw: String)]
    let body: String

    init(_ data: Data) throws {
        guard let text = String(bytes: data, encoding: .ascii), let split = text.range(of: "\r\n\r\n") else {
            throw ParseError.notASCIIOrNoBlankLine
        }
        var headers: [(String, String)] = []
        for line in text[..<split.lowerBound].components(separatedBy: "\r\n") {
            if line.hasPrefix(" "), let last = headers.popLast() {
                headers.append((last.0, last.1 + "\r\n" + line))
            } else if let colon = line.firstIndex(of: ":") {
                headers.append((String(line[..<colon]), String(line[line.index(after: colon)...]).trimmingPrefix(" ").description))
            }
        }
        self.headers = headers
        body = String(text[split.upperBound...])
    }

    func rawHeader(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.raw
    }

    /// Unfolded, as RFC 5322 §2.2.3 reads it.
    func header(_ name: String) -> String? {
        rawHeader(name)?.replacingOccurrences(of: "\r\n", with: "")
    }

    /// Unfolded, with RFC 2047 encoded words decoded and the space between two of them dropped.
    func decodedHeader(_ name: String) throws -> String? {
        guard let raw = rawHeader(name) else { return nil }
        let words = raw.components(separatedBy: "\r\n ").flatMap { $0.components(separatedBy: " ") }
        var result = ""
        var previousWasEncoded = false
        for (index, word) in words.enumerated() {
            let isEncoded = word.hasPrefix("=?") && word.hasSuffix("?=")
            if index > 0, !(isEncoded && previousWasEncoded) { result += " " }
            if isEncoded {
                let parts = word.dropFirst(2).dropLast(2).split(separator: "?", omittingEmptySubsequences: false)
                guard parts.count == 3, parts[0].lowercased() == "utf-8", parts[1].uppercased() == "B",
                      let bytes = Data(base64Encoded: String(parts[2]))
                else { throw ParseError.badEncodedWord(word) }
                result += String(bytes: bytes, encoding: .utf8) ?? ""
            } else {
                result += word
            }
            previousWasEncoded = isEncoded
        }
        return result
    }

    func decodedBody() throws -> String {
        guard let bytes = Data(base64Encoded: body.replacingOccurrences(of: "\r\n", with: "")),
              let text = String(bytes: bytes, encoding: .utf8)
        else { throw ParseError.badBody }
        return text
    }
}
