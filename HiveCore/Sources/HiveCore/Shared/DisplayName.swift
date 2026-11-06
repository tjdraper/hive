import Foundation

/// A name a person gives something, such as a device or the Hive itself, checked before it's stored and listed.
enum DisplayName {
    /// Long enough for any name a person gives a Mac, short enough to list.
    static let longest = 100

    static func validated(_ requested: String) -> String? {
        let name = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.count <= longest,
              !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { return nil }
        return name
    }
}
