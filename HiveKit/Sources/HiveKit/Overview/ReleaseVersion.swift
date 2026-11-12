/// A release's version, such as 2026.3 or 2026.3.1. Hive and Beekeeper are released together under one
/// number, so Beekeeper can tell when the Hive it manages is behind it.
public struct ReleaseVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let description: String
    /// Without trailing zeros, so 2026.3 and 2026.3.0 are the same version.
    private let parts: [Int]

    public init?(_ string: String) {
        let pieces = string.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = pieces.compactMap { piece in
            piece.allSatisfy { ("0"..."9").contains($0) } ? Int(piece) : nil
        }
        guard numbers.count == pieces.count else { return nil }
        description = string
        var parts = numbers
        while parts.count > 1, parts.last == 0 {
            parts.removeLast()
        }
        self.parts = parts
    }

    public static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        lhs.parts == rhs.parts
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(parts)
    }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }
}

extension ReleaseVersion: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let version = ReleaseVersion(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a release version")
        }
        self = version
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
