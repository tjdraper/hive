import Foundation

/// Reads a server's `~/.ssh/authorized_keys` as `sshd` does (sshd(8), "AUTHORIZED_KEYS FILE FORMAT"):
/// each line is optional options, then a key type, the key, and a comment. Options can hold quoted spaces.
enum AuthorizedKeysFile {
    struct Entry: Equatable {
        /// Exactly as it is in the file, so the same line can be found again.
        let line: String
        /// Such as `restrict,from="100.64.0.7"`. Nil when the line has none.
        let options: String?
        let key: OpenSSHPublicKey
    }

    /// Every line for `key`, exactly as written. None in a file that isn't UTF-8, since a line changed
    /// in reading it couldn't be found again to remove.
    static func entries(for key: OpenSSHPublicKey, in contents: Data) -> [Entry] {
        (String(bytes: contents, encoding: .utf8) ?? "")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { entry(String($0)) }
            .filter { $0.key == key }
    }

    /// The line for `key` with the same options `entry` has, so a new key is limited the same way.
    static func line(like entry: Entry, for key: OpenSSHPublicKey, comment: String) -> String {
        (entry.options.map { $0 + " " } ?? "") + key.line + " " + comment
    }

    static func entry(_ line: String) -> Entry? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        if let key = OpenSSHPublicKey(line: String(trimmed)) {
            return Entry(line: line, options: nil, key: key)
        }
        let options = optionsField(of: trimmed)
        let rest = trimmed.dropFirst(options.count).drop { $0 == " " || $0 == "\t" }
        guard !options.isEmpty, let key = OpenSSHPublicKey(line: String(rest)) else { return nil }
        return Entry(line: line, options: String(options), key: key)
    }

    /// Up to the first space or tab outside double quotes. A backslash keeps the quote after it inside them.
    private static func optionsField(of text: Substring) -> Substring {
        var isQuoted = false
        var isEscaped = false
        for index in text.indices {
            let character = text[index]
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = isQuoted
            } else if character == "\"" {
                isQuoted.toggle()
            } else if !isQuoted, character == " " || character == "\t" {
                return text[..<index]
            }
        }
        return text
    }
}
