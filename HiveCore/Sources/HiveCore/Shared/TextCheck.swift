import Foundation

/// Checks on text that ends up in a command Hive runs, or in a file name.
enum TextCheck {
    private static let lettersAndDigits = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    static func hasControlCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    /// ASCII letters, digits and `extra`, not starting with `-`, which a command would read as an option.
    static func isPlainName(_ text: String, extra: String, longest: Int) -> Bool {
        let allowed = CharacterSet(charactersIn: lettersAndDigits + extra)
        return !text.isEmpty
            && text.utf8.count <= longest
            && !text.hasPrefix("-")
            && text.unicodeScalars.allSatisfy(allowed.contains)
    }
}
