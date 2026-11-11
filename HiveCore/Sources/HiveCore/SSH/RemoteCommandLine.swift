import Foundation

/// A command for a server's shell. `ssh` hands the server one line, which its shell splits into words,
/// so every word from outside Hive is quoted.
enum RemoteCommandLine {
    static func line(_ words: [String]) -> String {
        words.map(quoted).joined(separator: " ")
    }

    /// In single quotes, which a POSIX shell reads literally, with any single quote closed, escaped and reopened.
    static func quoted(_ word: String) -> String {
        "'" + word.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
