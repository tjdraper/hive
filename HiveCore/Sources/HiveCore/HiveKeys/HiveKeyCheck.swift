import CryptoKit
import Foundation
import os

public enum HiveKeyCheckError: Error, Equatable {
    case identityKeyCouldNotSign
    case earlierSecretUnreadable
}

/// Uses both keys at start, before anything relies on them. Loading a Secure Enclave key doesn't
/// prove the Secure Enclave will use it, and only a secret sealed on an earlier start proves the
/// secrets already stored can still be opened.
public struct HiveKeyCheck {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Keys")

    let directory: URL
    let owner: uid_t

    public init(directory: URL, owner: uid_t = geteuid()) {
        self.directory = directory
        self.owner = owner
    }

    public func run(_ keys: HiveKeys) throws {
        try checkIdentity(keys.identity)
        try checkStorage(keys)
    }

    private func checkIdentity(_ key: any IdentitySigningKey) throws {
        let challenge = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        do {
            let signature = try key.signature(for: challenge)
            guard key.publicKey.isValidSignature(signature, for: challenge) else {
                throw HiveKeyCheckError.identityKeyCouldNotSign
            }
        } catch {
            Self.logger.fault("The identity key couldn't sign: \(String(describing: error), privacy: .public)")
            throw HiveKeyCheckError.identityKeyCouldNotSign
        }
        Self.logger.notice("The identity key signed")
    }

    private func checkStorage(_ keys: HiveKeys) throws {
        let sealer = SecretSealer(key: keys.storage)
        let file = OwnerOnlyFile(url: directory.appending(path: "key-check.sealed", directoryHint: .notDirectory), owner: owner)

        // Secrets sealed for a storage key that no longer exists can't be opened by anything.
        if keys.created.contains(.storage) { try file.remove() }

        if let sealed = try file.read() {
            do {
                _ = try sealer.open(SealedSecret(data: sealed))
            } catch {
                Self.logger.fault("Couldn't open the secret sealed on an earlier start: \(String(describing: error), privacy: .public)")
                throw HiveKeyCheckError.earlierSecretUnreadable
            }
            Self.logger.notice("Opened the secret sealed on an earlier start")
            return
        }

        let sealed = try sealer.seal(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
        _ = try sealer.open(sealed)
        try file.create(sealed.data)
        Self.logger.notice("Sealed a secret for later starts to open")
    }
}
