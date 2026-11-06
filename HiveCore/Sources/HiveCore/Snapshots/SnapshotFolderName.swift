import Foundation

/// Names on the drive: `Hive/<server>/<job>/<date-time>/` (§9).
enum SnapshotFolderName {
    static let partialSuffix = ".partial"
    /// Short enough that the whole name stays readable in Finder.
    static let longestName = 60
    static let shortIDLength = 8

    /// A server's or job's folder, from its name and its ID. The ID keeps two similar names, a rename,
    /// or a job added again under an old name from ever sharing a folder. The full ID is the fallback
    /// for the rare short one that's taken.
    static func candidates(name: String, id: UUID) -> [String] {
        let hex = id.uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let base = readable(name)
        return ["\(base) \(hex.prefix(shortIDLength))", "\(base) \(hex)"]
    }

    /// In UTC, so a repeated hour when the clocks go back can't give two snapshots the same name, and
    /// without colons, which Finder shows as slashes.
    static func snapshot(at date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeSeparator: .omitted, timeZone: .gmt))
    }

    static func partial(at date: Date) -> String {
        snapshot(at: date) + partialSuffix
    }

    /// Letters, digits, spaces and a little punctuation. Anything else, such as `/`, a control character
    /// or a leading `.`, which would hide the folder, becomes `-`.
    private static func readable(_ name: String) -> String {
        let kept = name.unicodeScalars.map { scalar -> String in
            let allowed = scalar.properties.isAlphabetic || scalar.properties.numericType != nil || " -_".unicodeScalars.contains(scalar)
            return allowed ? String(scalar) : "-"
        }
        let collapsed = kept.joined().split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let trimmed = String(collapsed.prefix(longestName)).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "-" : trimmed
    }
}
