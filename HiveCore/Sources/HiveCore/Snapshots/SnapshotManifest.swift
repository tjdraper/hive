import Foundation

/// `manifest.json` in each snapshot: whose it is, what it holds and whether it completed, so Hive's
/// catalog can be rebuilt from the drive (§9, F3). A partial snapshot has one too, marked incomplete.
struct SnapshotManifest: Codable, Equatable {
    static let fileName = "manifest.json"
    /// Raised whenever a field changes meaning or goes away, so a reader can tell a manifest it doesn't understand.
    static let currentFormat = 1

    struct Named: Codable, Equatable {
        let id: UUID
        let name: String
    }

    struct Directory: Codable, Equatable {
        /// Its path on the server.
        let path: String
        /// Where it is within `files/`.
        let folder: String
        /// Files disappeared on the server while they were being copied.
        let vanishedFiles: Bool
    }

    let format: Int
    let hiveID: UUID
    let snapshotID: UUID
    let server: Named
    let job: Named
    let startedAt: Date
    let completedAt: Date?
    let complete: Bool
    /// The directories copied so far, all of them once it's complete.
    let directories: [Directory]

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func decoded(from data: Data) throws -> SnapshotManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SnapshotManifest.self, from: data)
    }
}
