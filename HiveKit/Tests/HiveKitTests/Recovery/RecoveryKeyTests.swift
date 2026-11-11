import CryptoKit
import Foundation
@testable import HiveKit
import Testing

struct RecoveryKeyTests {
    /// Recovery files written for this code must keep opening with it, whatever changes here.
    static let knownCode = "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYQ"
    static let knownPublicKey = "1nD5TRSZjOxjBcLBmoL5zVMX6peia6AOIRcyLGF2UB0="

    @Test("A code reads back as the same key")
    func roundTrip() throws {
        // Arrange
        let key = RecoveryKey()

        // Act
        let read = try RecoveryKey(code: key.code)

        // Assert
        #expect(read.publicKey.rawRepresentation == key.publicKey.rawRepresentation)
        #expect(key.groups.count == RecoveryKey.groupCount)
        #expect(key.groups.allSatisfy { $0.count == RecoveryKey.groupLength })
    }

    @Test("A code always makes the same key")
    func knownKey() throws {
        // Act
        let key = try RecoveryKey(code: Self.knownCode)

        // Assert
        #expect(key.publicKey.rawRepresentation.base64EncodedString() == Self.knownPublicKey)
        #expect(key.code == Self.knownCode)
    }

    @Test("Two new keys differ")
    func newKeysDiffer() {
        #expect(RecoveryKey().code != RecoveryKey().code)
    }

    @Test("A code reads the same in any case, without dashes, with spaces, and with I, L and O for 1 and 0")
    func lenientReading() throws {
        // Arrange
        let key = try RecoveryKey(code: Self.knownCode)
        let typed = [
            Self.knownCode.lowercased(),
            Self.knownCode.replacingOccurrences(of: "-", with: ""),
            Self.knownCode.replacingOccurrences(of: "-", with: " "),
            Self.knownCode.replacingOccurrences(of: "1", with: "I"),
            Self.knownCode.replacingOccurrences(of: "1", with: "l"),
            Self.knownCode.replacingOccurrences(of: "0", with: "O"),
        ]

        for code in typed {
            // Act
            let read = try RecoveryKey(code: code)

            // Assert
            #expect(read.publicKey.rawRepresentation == key.publicKey.rawRepresentation, "\(code)")
        }
    }

    @Test("Every single mistyped character is caught by the check character")
    func catchesEveryMistypedCharacter() throws {
        // Arrange
        let key = RecoveryKey()
        let characters = Array(key.groups.joined())

        for position in characters.indices {
            for replacement in RecoveryKey.alphabet where replacement != characters[position] {
                var mistyped = characters
                mistyped[position] = replacement

                // Act
                let result = Result { () throws(RecoveryKeyCodeError) in try RecoveryKey(code: String(mistyped)) }

                // Assert
                #expect(throws: RecoveryKeyCodeError.mistyped) { try result.get() }
            }
        }
    }

    @Test("A code that's too short, too long or holds a character no code has is refused")
    func refusesMalformed() {
        let code = RecoveryKey().code
        #expect(throws: RecoveryKeyCodeError.wrongLength) { try RecoveryKey(code: String(code.dropLast())) }
        #expect(throws: RecoveryKeyCodeError.wrongLength) { try RecoveryKey(code: code + "0") }
        #expect(throws: RecoveryKeyCodeError.unknownCharacter) { try RecoveryKey(code: "U" + code.dropFirst()) }
        #expect(throws: RecoveryKeyCodeError.unknownCharacter) { try RecoveryKey(code: code + "!") }
    }
}
