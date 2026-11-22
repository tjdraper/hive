#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// What Scout's update key vouches for: one build's version, system and CPU, and SHA-256. A signature
/// over the binary alone would let an older genuine release pass for a newer one.
///
/// As a file, the statement's lines come first and the signature last, over the bytes of those lines:
///
///     hive-scout release statement
///     version 0.2.0
///     platform linux-x86_64
///     sha256 <64 lower-case hex digits>
///     signature <base64 of the Ed25519 signature>
public struct ReleaseStatement: Equatable, Sendable {
    /// Ties the signature to this kind of statement, so nothing else signed with the key can pass for one.
    static let heading = "hive-scout release statement"
    /// Far longer than a statement, so a request can't carry anything large in its place.
    public static let longest = 1024

    public let version: ScoutVersion
    /// As `ScoutRelease.platform` names it, such as `linux-x86_64`.
    public let platform: String
    public let sha256: [UInt8]

    public init(version: ScoutVersion, platform: String, sha256: [UInt8]) {
        self.version = version
        self.platform = platform
        self.sha256 = sha256
    }

    /// The bytes the signature is over.
    public var signedText: String {
        let hash = sha256.map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
        return "\(Self.heading)\nversion \(version)\nplatform \(platform)\nsha256 \(hash)\n"
    }

    /// A statement file split into what it says, whose `signedText` the signature is over, and the
    /// signature. Nil for anything but the lines `signedText` writes, exactly, then one signature line.
    public static func parse(_ file: String) -> (statement: Self, signature: [UInt8])? {
        guard file.utf8.count <= longest, file.hasSuffix("\n") else { return nil }
        let lines = file.dropLast().split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count == 5, lines[0] == heading,
              let version = value(of: "version", in: lines[1]).flatMap(ScoutVersion.init(parsing:)),
              let platform = value(of: "platform", in: lines[2]),
              let sha256 = value(of: "sha256", in: lines[3]).flatMap(bytes(fromHex:)), sha256.count == 32,
              let signature = value(of: "signature", in: lines[4]).flatMap({ Data(base64Encoded: String($0)) })
        else { return nil }
        let statement = Self(version: version, platform: String(platform), sha256: sha256)
        // Only the one way of writing a statement is ever checked, so what's signed is what's read.
        guard lines[0...3].joined(separator: "\n") + "\n" == statement.signedText else { return nil }
        return (statement, Array(signature))
    }

    private static func value(of name: String, in line: Substring) -> Substring? {
        let value = line.dropFirst(name.count + 1)
        return line.hasPrefix(name + " ") && !value.isEmpty ? value : nil
    }

    /// Lower case only, as `signedText` writes it.
    private static func bytes(fromHex text: Substring) -> [UInt8]? {
        let digits = Array(text.utf8)
        guard digits.count.isMultiple(of: 2) else { return nil }
        return stride(from: 0, to: digits.count, by: 2).reduce(into: [UInt8]?.some([])) { bytes, index in
            guard let high = nibble(digits[index]), let low = nibble(digits[index + 1]) else { bytes = nil; return }
            bytes?.append(high << 4 | low)
        }
    }

    private static func nibble(_ digit: UInt8) -> UInt8? {
        switch digit {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): digit - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): digit - UInt8(ascii: "a") + 10
        default: nil
        }
    }
}

/// Scout's version: three numbers, such as `0.2.0`, compared in turn.
public struct ScoutVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let parts: [Int]

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        parts = [major, minor, patch]
    }

    public init?(parsing text: some StringProtocol) {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        // Digits only, without a leading zero, so each version is written one way.
        let parts = pieces.compactMap { piece -> Int? in
            guard (1...6).contains(piece.utf8.count), piece == "0" || !piece.hasPrefix("0"),
                  piece.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) })
            else { return nil }
            return Int(piece)
        }
        guard pieces.count == 3, parts.count == 3 else { return nil }
        self.parts = parts
    }

    public var description: String {
        parts.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }
}
