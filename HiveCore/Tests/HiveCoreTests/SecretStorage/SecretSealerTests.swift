import CryptoKit
import Foundation
@testable import HiveCore
import Testing

struct SecretSealerTests {
    private let secret = Data("correct horse battery staple".utf8)
    private let sealer = SecretSealer(key: P256.KeyAgreement.PrivateKey())

    @Test("A sealed secret opens to the same secret")
    func roundTrip() throws {
        // Arrange
        let sealed = try sealer.seal(secret)

        // Act
        let opened = try sealer.open(sealed)

        // Assert
        #expect(opened == secret)
        #expect(sealed.data.range(of: secret) == nil)
    }

    @Test("Sealing the same secret twice gives different results")
    func freshEachTime() throws {
        // Act
        let first = try sealer.seal(secret)
        let second = try sealer.seal(secret)

        // Assert
        #expect(first != second)
    }

    @Test("A changed byte anywhere fails to open, never opening to something else")
    func changedByteFails() throws {
        // Arrange
        let sealed = try sealer.seal(secret)

        for index in sealed.data.indices {
            var changed = sealed.data
            changed[index] ^= 0x01

            // Act / Assert
            #expect(throws: SecretSealingError.self, "byte \(index)") { try sealer.open(SealedSecret(data: changed)) }
        }
    }

    @Test("A shortened sealed secret fails to open")
    func truncatedFails() throws {
        // Arrange
        let sealed = try sealer.seal(secret)

        for length in [0, 1, 66, sealed.data.count - 1] {
            let truncated = SealedSecret(data: sealed.data.prefix(length))

            // Act / Assert
            #expect(throws: SecretSealingError.self, "length \(length)") { try sealer.open(truncated) }
        }
    }

    @Test("A secret sealed for one storage key can't be opened with another")
    func otherKeyFails() throws {
        // Arrange
        let sealed = try sealer.seal(secret)
        let otherSealer = SecretSealer(key: P256.KeyAgreement.PrivateKey())

        // Act / Assert
        #expect(throws: SecretSealingError.couldNotOpen) { try otherSealer.open(sealed) }
    }

    @Test("An unknown format version is refused", arguments: [UInt8(0), 2, 255])
    func unknownVersionRefused(version: UInt8) throws {
        // Arrange
        var data = try sealer.seal(secret).data
        data[data.startIndex] = version

        // Act / Assert
        #expect(throws: SecretSealingError.unsupportedVersion(version)) { try sealer.open(SealedSecret(data: data)) }
    }

    @Test("An empty secret seals and opens")
    func emptySecret() throws {
        // Arrange
        let sealed = try sealer.seal(Data())

        // Act
        let opened = try sealer.open(sealed)

        // Assert
        #expect(opened.isEmpty)
    }
}
