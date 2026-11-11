import CryptoKit
import Foundation

public enum RecoveryKeyCodeError: Error, Equatable {
    case wrongLength
    case unknownCharacter
    /// The check character doesn't match, so the code was mistyped.
    case mistyped
}

/// The key recovery files are encrypted to (§14). Its private half is a code to save in a password
/// manager or print: 31 random Crockford base32 characters and a check character, in groups of four.
/// Hive is only ever given the public half.
///
/// The code's 155 random bits are stretched into an X25519 key with HKDF, so any code that passes its
/// check is a valid key.
public struct RecoveryKey: Sendable {
    public static let groupCount = 8
    public static let groupLength = 4
    static let randomLength = groupCount * groupLength - 1
    /// Crockford's base32 (https://www.crockford.com/base32.html), which leaves out I, L, O and U so
    /// nothing reads as another character.
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    private static let derivationSalt = Data("Hive recovery key".utf8)
    private static let derivationInfo = Data("X25519 v1".utf8)

    /// Each 0 to 31, without the check character.
    let symbols: [UInt8]

    /// A new key from the system's secure random generator.
    public init() {
        var generator = SystemRandomNumberGenerator()
        symbols = (0 ..< Self.randomLength).map { _ in UInt8.random(in: 0 ..< 32, using: &generator) }
    }

    /// A code as the person typed it: any case, with or without dashes and spaces, reading I and L as 1 and O as 0.
    public init(code: String) throws(RecoveryKeyCodeError) {
        let values = try Self.values(of: code)
        guard values.count == Self.randomLength + 1 else { throw RecoveryKeyCodeError.wrongLength }
        guard Self.isChecked(values) else { throw RecoveryKeyCodeError.mistyped }
        symbols = Array(values.dropLast())
    }

    /// The groups of four, the last ending in the check character.
    public var groups: [String] {
        let characters = (symbols + [Self.checkValue(for: symbols)]).map { Self.alphabet[Int($0)] }
        return stride(from: 0, to: characters.count, by: Self.groupLength).map {
            String(characters[$0 ..< $0 + Self.groupLength])
        }
    }

    public var code: String {
        groups.joined(separator: "-")
    }

    public var privateKey: Curve25519.KeyAgreement.PrivateKey {
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(symbols)),
            salt: Self.derivationSalt,
            info: Self.derivationInfo,
            outputByteCount: 32
        )
        // Any 32 bytes are an X25519 private key, so this can't fail.
        // swiftlint:disable:next force_try
        return derived.withUnsafeBytes { try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: $0) }
    }

    public var publicKey: Curve25519.KeyAgreement.PublicKey {
        privateKey.publicKey
    }

    private static func values(of text: String) throws(RecoveryKeyCodeError) -> [UInt8] {
        var values: [UInt8] = []
        for character in text.uppercased() {
            switch character {
            case "-", " ", "\t", "\n":
                continue
            case "I", "L":
                values.append(1)
            case "O":
                values.append(0)
            default:
                guard let index = alphabet.firstIndex(of: character) else { throw RecoveryKeyCodeError.unknownCharacter }
                values.append(UInt8(index))
            }
        }
        return values
    }

    /// Luhn mod N (https://en.wikipedia.org/wiki/Luhn_mod_N_algorithm), which catches every single
    /// mistyped character and most pairs of neighbors swapped.
    static func checkValue(for values: [UInt8]) -> UInt8 {
        UInt8((32 - luhnSum(values, doublingFirst: true) % 32) % 32)
    }

    private static func isChecked(_ values: [UInt8]) -> Bool {
        luhnSum(values, doublingFirst: false) % 32 == 0
    }

    /// Works from the right, doubling every other value. Without its check character a code's last
    /// value is doubled, and with it the check character isn't.
    private static func luhnSum(_ values: [UInt8], doublingFirst: Bool) -> Int {
        var doubles = doublingFirst
        var sum = 0
        for value in values.reversed() {
            let addend = Int(value) * (doubles ? 2 : 1)
            sum += addend / 32 + addend % 32
            doubles.toggle()
        }
        return sum
    }
}
