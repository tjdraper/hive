import CryptoKit
import Foundation
@testable import HiveKit
import Security
import SwiftASN1
import Testing
import X509

struct PinnedTrustEvaluatorTests {
    private let key = P256.Signing.PrivateKey()
    private let now = Date()
    private let day: TimeInterval = 24 * 60 * 60

    private var evaluator: PinnedTrustEvaluator {
        PinnedTrustEvaluator(pin: PublicKeyPin(publicKey: key.publicKey))
    }

    @Test("A certificate with the pinned key passes")
    func pinnedKeyPasses() throws {
        // Arrange
        let trust = try makeTrust(
            certificate: makeCertificate(key: Certificate.PrivateKey(key), validFrom: now - day, until: now + day),
            host: "hive.example"
        )

        // Act, Assert
        #expect(evaluator.accepts(trust))
    }

    @Test("A certificate with the pinned key passes when expired")
    func expiredCertificatePasses() throws {
        // Arrange
        let trust = try makeTrust(
            certificate: makeCertificate(key: Certificate.PrivateKey(key), validFrom: now - 30 * day, until: now - day),
            host: "hive.example"
        )

        // Act, Assert
        #expect(evaluator.accepts(trust))
    }

    @Test("A certificate with the pinned key passes when it names another host")
    func otherHostnamePasses() throws {
        // Arrange
        let trust = try makeTrust(
            certificate: makeCertificate(key: Certificate.PrivateKey(key), validFrom: now - day, until: now + day),
            host: "somewhere-else.example"
        )

        // Act, Assert
        #expect(evaluator.accepts(trust))
    }

    @Test("A certificate with a different key fails")
    func differentKeyFails() throws {
        // Arrange
        let other = P256.Signing.PrivateKey()
        let trust = try makeTrust(
            certificate: makeCertificate(key: Certificate.PrivateKey(other), validFrom: now - day, until: now + day),
            host: "hive.example"
        )

        // Act, Assert
        #expect(!evaluator.accepts(trust))
    }

    @Test("A certificate with a key that isn't P-256 fails")
    func otherCurveFails() throws {
        // Arrange
        let other = P384.Signing.PrivateKey()
        let trust = try makeTrust(
            certificate: makeCertificate(key: Certificate.PrivateKey(other), validFrom: now - day, until: now + day),
            host: "hive.example"
        )

        // Act, Assert
        #expect(!evaluator.accepts(trust))
    }

    @Test("A pairing code with a wrong key hash refuses the Hive's certificate, and one with the right hash accepts it")
    func pairingCodePin() throws {
        // Arrange
        let trust = try makeTrust(
            certificate: makeCertificate(key: Certificate.PrivateKey(key), validFrom: now - day, until: now + day),
            host: "hive.example"
        )
        let address = HiveAddress(host: "hive.example", port: 4483)
        let token = Data(repeating: 9, count: PairingCode.tokenLength)
        let otherPin = PublicKeyPin(publicKey: P256.Signing.PrivateKey().publicKey)
        let wrong = PairingCode(hiveID: UUID(), pin: otherPin, token: token, addresses: [address])
        let right = PairingCode(hiveID: UUID(), pin: PublicKeyPin(publicKey: key.publicKey), token: token, addresses: [address])

        // Act
        let wrongPin = try #require(PairingCode(text: wrong.text)).pin
        let rightPin = try #require(PairingCode(text: right.text)).pin

        // Assert
        #expect(!PinnedTrustEvaluator(pin: wrongPin).accepts(trust))
        #expect(PinnedTrustEvaluator(pin: rightPin).accepts(trust))
    }

    @Test("A pin is the SHA-256 hash of the key's X9.63 form")
    func pinHashesX963() {
        // Act
        let pin = PublicKeyPin(publicKey: key.publicKey)

        // Assert
        #expect(pin.sha256 == Data(SHA256.hash(data: key.publicKey.x963Representation)))
    }

    /// Self-signed, naming hive.example.
    private func makeCertificate(key: Certificate.PrivateKey, validFrom: Date, until: Date) throws -> SecCertificate {
        let name = try DistinguishedName {
            CommonName("hive.example")
        }
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: key.publicKey,
            notValidBefore: validFrom,
            notValidAfter: until,
            issuer: name,
            subject: name,
            extensions: Certificate.Extensions {
                SubjectAlternativeNames([.dnsName("hive.example")])
            },
            issuerPrivateKey: key
        )
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        return try #require(SecCertificateCreateWithData(nil, Data(serializer.serializedBytes) as CFData))
    }

    /// The trust a connection to `host` would hand Beekeeper.
    private func makeTrust(certificate: SecCertificate, host: String) throws -> SecTrust {
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, host as CFString), &trust)
        #expect(status == errSecSuccess)
        return try #require(trust)
    }
}
