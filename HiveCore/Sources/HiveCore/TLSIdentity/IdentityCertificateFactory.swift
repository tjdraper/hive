import Foundation
import X509

/// Hive's self-signed certificate. Devices pin the key it holds and ignore the rest, so it only has to
/// carry that key through a TLS handshake.
struct IdentityCertificateFactory {
    static let lifetime: TimeInterval = 3652 * 24 * 60 * 60

    func issue(for key: any IdentitySigningKey, at date: Date) throws -> Certificate {
        let name = try DistinguishedName {
            CommonName("Hive")
        }
        return try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(key.publicKey),
            notValidBefore: date,
            notValidAfter: date.addingTimeInterval(Self.lifetime),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true))
                try ExtendedKeyUsage([.serverAuth])
            },
            issuerPrivateKey: key.certificateIssuer
        )
    }
}
