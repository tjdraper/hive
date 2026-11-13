import Foundation

/// What a recovery file holds (§14): the Hive ID and its whole configuration, every secret opened, so
/// Hive can be brought back on a Mac whose Secure Enclave has never seen them (F3). Devices aren't in
/// it, since every device pairs again after a restore, and neither is anything Hive can rebuild, such
/// as the snapshot catalog, or only records, such as the logs.
///
/// The fields follow the store's columns, so a restore can put each value back where it came from.
/// `currentFormat` goes up whenever a field changes meaning or goes away, so a reader can tell a file
/// it doesn't understand.
struct RecoveryContents: Codable, Equatable {
    static let currentFormat = 1

    struct Hive: Codable, Equatable {
        let id: UUID
        let createdAt: Date
        let name: String
        /// `StoredNetworkAccess`.
        let networkAccess: String
        let listenAddress: String?
        /// Nil while it's the default.
        let port: Int?
        /// `[AddressOption]` as the store keeps it. Missing from files written before there were any.
        let addressOptions: String?
        /// Missing from files written before Hive advertised itself, which then starts doing so.
        let advertisesOnLocalNetwork: Bool?
        /// Chosen again after a restore, since a drive restored from a Mac backup has a new volume UUID.
        let backupDrive: BackupDrive?
    }

    struct BackupDrive: Codable, Equatable {
        let volumeUUID: String
        let name: String
    }

    struct Server: Codable, Equatable {
        let id: UUID
        let name: String
        let host: String
        let port: Int
        let user: String
        let quotaBytes: Int64?
        let createdAt: Date
        /// The host key a device confirmed, as `OpenSSHPublicKey.line` writes it. There's no other
        /// `known_hosts` to bring back (C2).
        let hostKey: String?
        let sshKey: SSHKey?
        /// Kept, so snapshots after a restore go in the same folder as those before.
        let snapshotFolder: String?
        let jobs: [Job]
    }

    struct SSHKey: Codable, Equatable {
        /// A secret: the Ed25519 seed.
        let seed: Data
        let publicKey: String
    }

    struct Job: Codable, Equatable {
        let id: UUID
        let name: String
        let dailySnapshots: Int
        let monthlySnapshots: Int
        let createdAt: Date
        let snapshotFolder: String?
        let directories: [Directory]
        let databases: [Database]
        let minutesOfDay: [Int]
    }

    struct Directory: Codable, Equatable {
        let path: String
        let folder: String
    }

    struct Database: Codable, Equatable {
        let id: UUID
        /// `DatabaseKind`.
        let kind: String
        /// Nil for a database running on the server itself.
        let serviceName: String?
        let user: String
        let name: String
        /// A secret, as UTF-8.
        let password: Data?
    }

    struct Email: Codable, Equatable {
        let host: String
        let port: Int
        /// `EmailSecurity`.
        let security: String
        let username: String
        let senderAddress: String
        let recipients: [String]
        /// A secret, as UTF-8.
        let password: Data?
    }

    let format: Int
    let writtenAt: Date
    let hive: Hive
    let servers: [Server]
    let email: Email?

    /// The same contents with every secret passed through `transform`, such as to open the sealed
    /// values read from the store.
    func mappingSecrets(_ transform: (Data) throws -> Data) rethrows -> RecoveryContents {
        RecoveryContents(
            format: format,
            writtenAt: writtenAt,
            hive: hive,
            servers: try servers.map { try $0.mappingSecrets(transform) },
            email: try email.map { try $0.mappingSecrets(transform) }
        )
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        // Sorted, so the same contents always encode the same and can be compared by hash.
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decoded(from data: Data) throws -> RecoveryContents {
        try JSONDecoder().decode(RecoveryContents.self, from: data)
    }
}

private extension RecoveryContents.Server {
    func mappingSecrets(_ transform: (Data) throws -> Data) rethrows -> Self {
        Self(
            id: id,
            name: name,
            host: host,
            port: port,
            user: user,
            quotaBytes: quotaBytes,
            createdAt: createdAt,
            hostKey: hostKey,
            sshKey: try sshKey.map { RecoveryContents.SSHKey(seed: try transform($0.seed), publicKey: $0.publicKey) },
            snapshotFolder: snapshotFolder,
            jobs: try jobs.map { try $0.mappingSecrets(transform) }
        )
    }
}

private extension RecoveryContents.Job {
    func mappingSecrets(_ transform: (Data) throws -> Data) rethrows -> Self {
        Self(
            id: id,
            name: name,
            dailySnapshots: dailySnapshots,
            monthlySnapshots: monthlySnapshots,
            createdAt: createdAt,
            snapshotFolder: snapshotFolder,
            directories: directories,
            databases: try databases.map { database in
                RecoveryContents.Database(
                    id: database.id,
                    kind: database.kind,
                    serviceName: database.serviceName,
                    user: database.user,
                    name: database.name,
                    password: try database.password.map(transform)
                )
            },
            minutesOfDay: minutesOfDay
        )
    }
}

private extension RecoveryContents.Email {
    func mappingSecrets(_ transform: (Data) throws -> Data) rethrows -> Self {
        Self(
            host: host,
            port: port,
            security: security,
            username: username,
            senderAddress: senderAddress,
            recipients: recipients,
            password: try password.map(transform)
        )
    }
}
