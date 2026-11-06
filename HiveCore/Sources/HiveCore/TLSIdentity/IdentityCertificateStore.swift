import Foundation
import os
import SwiftASN1
import X509

/// The certificate for the identity key, saved in the data directory and issued again whenever it no
/// longer fits that key.
public struct IdentityCertificateStore {
    static let fileName = "identity.cert"
    /// Beekeeper ignores expiry. Reissuing early keeps the certificate valid for anything else that
    /// inspects it, such as `openssl s_client`.
    static let reissueWithin: TimeInterval = 365 * 24 * 60 * 60

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "TLSIdentity")

    private enum ReissueReason: String {
        case missing
        case unreadable
        case otherKey = "for another key"
        case nearExpiry = "near expiry"
    }

    private enum SavedCertificate {
        case usable(Certificate)
        case unusable(ReissueReason)
    }

    let directory: URL
    let owner: uid_t

    public init(directory: URL, owner: uid_t = geteuid()) {
        self.directory = directory
        self.owner = owner
    }

    public func loadOrIssue(for key: any IdentitySigningKey, at now: Date = Date()) throws -> Certificate {
        let file = OwnerOnlyFile(url: directory.appending(path: Self.fileName, directoryHint: .notDirectory), owner: owner)

        let reason: ReissueReason
        switch examine(try file.read(), for: key, at: now) {
        case .usable(let certificate):
            Self.logger.notice("Loaded the identity certificate")
            return certificate
        case .unusable(let unusableReason):
            reason = unusableReason
        }

        let certificate = try IdentityCertificateFactory().issue(for: key, at: now)
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        try file.remove()
        try file.create(Data(serializer.serializedBytes))
        Self.logger.notice("Issued the identity certificate, the saved one was \(reason.rawValue, privacy: .public)")
        return certificate
    }

    private func examine(_ saved: Data?, for key: any IdentitySigningKey, at now: Date) -> SavedCertificate {
        guard let saved else { return .unusable(.missing) }
        guard let certificate = try? Certificate(derEncoded: Array(saved)) else { return .unusable(.unreadable) }
        guard certificate.publicKey == Certificate.PublicKey(key.publicKey) else { return .unusable(.otherKey) }
        guard certificate.notValidAfter > now.addingTimeInterval(Self.reissueWithin) else { return .unusable(.nearExpiry) }
        return .usable(certificate)
    }
}
