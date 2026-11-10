import Foundation

/// An email Hive sends, as plain text. The settings say who it's from and who it goes to.
struct EmailMessage: Sendable {
    let subject: String
    let body: String
}

/// Writes a message as RFC 5322 text with MIME, ready for SMTP's `DATA`: CRLF line endings, every
/// line ASCII and short enough for any server, and any text in UTF-8.
struct EmailMessageBuilder {
    /// RFC 5322 asks for lines of at most 78 characters.
    static let lineLength = 78
    /// RFC 2047 caps an encoded word at 75 characters.
    static let encodedWordLength = 75

    let senderName: String
    let senderAddress: String
    let recipients: [String]
    let date: Date
    let timeZone: TimeZone
    let messageID: UUID

    func build(_ message: EmailMessage) -> Data {
        var headers = [
            "Date: \(Self.dateText(date, timeZone: timeZone))",
            "From: \(Self.displayName(senderName)) <\(senderAddress)>",
            Self.folded("To: " + recipients.joined(separator: ", ")),
            Self.subjectLine(message.subject),
            "Message-ID: <\(messageID.uuidString.lowercased())@\(Self.domain(of: senderAddress))>",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Transfer-Encoding: base64",
            "Auto-Submitted: auto-generated",
        ]
        headers.append("")
        let normalized = message.body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        let body = Data(normalized.utf8).base64EncodedString(
            options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed]
        )
        return Data((headers.joined(separator: "\r\n") + "\r\n" + body + "\r\n").utf8)
    }

    /// RFC 5322 §3.3, in English whatever the Mac's language.
    static func dateText(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }

    /// Quoted when it's plain ASCII, and encoded otherwise.
    static func displayName(_ name: String) -> String {
        let isPlain = name.unicodeScalars.allSatisfy { $0.isASCII && $0.value >= 0x20 && $0.value < 0x7F && $0 != "\"" && $0 != "\\" }
        return isPlain && name.count <= 60 ? "\"\(name)\"" : encodedWords(name, firstLinePrefix: "From: ").joined(separator: "\r\n ")
    }

    static func subjectLine(_ subject: String) -> String {
        let isPlain = subject.unicodeScalars.allSatisfy { $0.isASCII && $0.value >= 0x20 && $0.value < 0x7F }
        // A plain subject that happens to look like an encoded word would be decoded by the mail app.
        if isPlain, !subject.contains("=?") {
            return folded("Subject: " + subject)
        }
        return "Subject: " + encodedWords(subject, firstLinePrefix: "Subject: ").joined(separator: "\r\n ")
    }

    /// RFC 2047 encoded words, each whole characters of UTF-8 in base64, short enough that each sits on
    /// its own line, the first after `firstLinePrefix`.
    static func encodedWords(_ text: String, firstLinePrefix: String) -> [String] {
        let wrapping = "=?utf-8?B??=".count
        var words: [String] = []
        var pending = Data()
        for character in text {
            let bytes = Data(String(character).utf8)
            let room = encodedWordLength - wrapping - (words.isEmpty ? firstLinePrefix.count : 1)
            if !pending.isEmpty, base64Length(pending.count + bytes.count) > room {
                words.append("=?utf-8?B?\(pending.base64EncodedString())?=")
                pending = Data()
            }
            pending.append(bytes)
        }
        if !pending.isEmpty || words.isEmpty {
            words.append("=?utf-8?B?\(pending.base64EncodedString())?=")
        }
        return words
    }

    /// Breaks a header of plain ASCII at spaces, so no line is longer than RFC 5322 asks, where it can.
    static func folded(_ header: String) -> String {
        var lines: [String] = []
        var line = ""
        for word in header.split(separator: " ", omittingEmptySubsequences: false) {
            if line.isEmpty {
                line = String(word)
            } else if line.count + 1 + word.count > lineLength {
                lines.append(line)
                line = String(word)
            } else {
                line += " " + word
            }
        }
        lines.append(line)
        return lines.joined(separator: "\r\n ")
    }

    private static func base64Length(_ count: Int) -> Int {
        (count + 2) / 3 * 4
    }

    private static func domain(of address: String) -> String {
        address.split(separator: "@").last.map(String.init) ?? "hive.invalid"
    }
}
