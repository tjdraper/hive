import Crypto
@testable import ScoutCore
import Testing

struct HiveKeyPinTests {
    @Test("Hive's own key matches its pin")
    func matchingKey() {
        // Arrange
        let key = P256.Signing.PrivateKey().publicKey
        let pin = HiveKeyPin(publicKey: key)

        // Act
        let matches = pin.matches(subjectPublicKeyInfo: Array(key.derRepresentation))

        // Assert
        #expect(matches)
    }

    @Test("Any other key is refused")
    func otherKey() {
        // Arrange
        let pin = HiveKeyPin(publicKey: P256.Signing.PrivateKey().publicKey)
        let other = P256.Signing.PrivateKey().publicKey

        // Act
        let matches = pin.matches(subjectPublicKeyInfo: Array(other.derRepresentation))

        // Assert
        #expect(!matches)
    }

    @Test("A key that isn't P-256 is refused, even one with the same pinned hash in another form")
    func otherKeyType() {
        // Arrange
        let p384 = P384.Signing.PrivateKey().publicKey
        let pin = HiveKeyPin(sha256: Array(SHA256.hash(data: p384.x963Representation)))

        // Act
        let matches = pin.matches(subjectPublicKeyInfo: Array(p384.derRepresentation))

        // Assert
        #expect(!matches)
    }

    @Test("A pin is read from 64 hex digits, and nothing else")
    func hex() {
        let hex = String(repeating: "0f", count: 32)
        #expect(HiveKeyPin(hex: hex)?.sha256 == Array(repeating: 0x0F, count: 32))
        #expect(HiveKeyPin(hex: hex.uppercased())?.sha256 == Array(repeating: 0x0F, count: 32))
        #expect(HiveKeyPin(hex: String(hex.dropLast(2))) == nil)
        #expect(HiveKeyPin(hex: hex + "00") == nil)
        #expect(HiveKeyPin(hex: String(hex.dropLast()) + "g") == nil)
        #expect(HiveKeyPin(hex: String(hex.dropLast(2)) + "+f") == nil)
    }
}
