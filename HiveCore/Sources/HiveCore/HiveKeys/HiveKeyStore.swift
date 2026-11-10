import Foundation
import os

public enum HiveKeyKind: String, Sendable, CaseIterable {
    case identity
    case storage

    var fileName: String {
        "\(rawValue).key"
    }
}

public struct HiveKeys: Sendable {
    public let identity: any IdentitySigningKey
    public let storage: any SecretStorageKey
    /// The kinds created on this start, rather than loaded from an earlier one.
    public let created: Set<HiveKeyKind>
}

public enum HiveKeyStoreError: Error, Equatable {
    case couldNotCreate(HiveKeyKind)
    case couldNotLoad(HiveKeyKind)
}

/// Hive's two keys, saved in its data directory. A saved key that won't load is never replaced: a
/// new storage key would leave every secret unreadable, and a new identity key would unpair every
/// device, all because of what may be a passing failure. Only a device's confirmed request replaces
/// the identity key.
public struct HiveKeyStore: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Keys")

    let directory: URL
    let factory: any HiveKeyFactory
    let owner: uid_t

    public init(directory: URL, factory: any HiveKeyFactory = SecureEnclaveKeyFactory(), owner: uid_t = geteuid()) {
        self.directory = directory
        self.factory = factory
        self.owner = owner
    }

    public func loadOrCreate() throws -> HiveKeys {
        var created: Set<HiveKeyKind> = []
        let identity = try loadOrCreate(.identity, created: &created, load: factory.identityKey, make: factory.makeIdentityKey)
        let storage = try loadOrCreate(.storage, created: &created, load: factory.storageKey, make: factory.makeStorageKey)
        return HiveKeys(identity: identity, storage: storage, created: created)
    }

    /// A new identity key, not yet saved, so making it can fail without changing anything.
    func makeIdentityKey() throws -> CreatedKey<any IdentitySigningKey> {
        do {
            return try factory.makeIdentityKey()
        } catch {
            Self.logger.fault("Couldn't create a new identity key: \(String(describing: error), privacy: .public)")
            throw HiveKeyStoreError.couldNotCreate(.identity)
        }
    }

    /// Saved over the old one, which every paired device's pin names. Hive uses it from its next start,
    /// when it issues a certificate for it.
    func replaceIdentityKey(with key: CreatedKey<any IdentitySigningKey>) throws {
        let file = OwnerOnlyFile(url: directory.appending(path: HiveKeyKind.identity.fileName, directoryHint: .notDirectory), owner: owner)
        try file.replace(key.savedForm)
        Self.logger.notice("Replaced the identity key")
    }

    private func loadOrCreate<Key>(
        _ kind: HiveKeyKind,
        created: inout Set<HiveKeyKind>,
        load: (Data) throws -> Key,
        make: () throws -> CreatedKey<Key>
    ) throws -> Key {
        let file = OwnerOnlyFile(url: directory.appending(path: kind.fileName, directoryHint: .notDirectory), owner: owner)

        if let savedForm = try file.read() {
            do {
                let key = try load(savedForm)
                Self.logger.notice("Loaded the \(kind.rawValue, privacy: .public) key")
                return key
            } catch {
                Self.logger.fault(
                    "Couldn't load the \(kind.rawValue, privacy: .public) key: \(String(describing: error), privacy: .public)"
                )
                throw HiveKeyStoreError.couldNotLoad(kind)
            }
        }

        let new: CreatedKey<Key>
        do {
            new = try make()
        } catch {
            Self.logger.fault(
                "Couldn't create the \(kind.rawValue, privacy: .public) key: \(String(describing: error), privacy: .public)"
            )
            throw HiveKeyStoreError.couldNotCreate(kind)
        }
        try file.create(new.savedForm)
        created.insert(kind)
        Self.logger.notice("Created the \(kind.rawValue, privacy: .public) key")
        return new.key
    }
}
