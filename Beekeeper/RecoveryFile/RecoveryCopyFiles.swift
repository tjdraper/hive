import Foundation
import HiveKit

/// Where this device keeps its copies of one Hive's recovery file: one in Beekeeper's own folder, and on
/// the Mac another in a folder the person chose, such as one in iCloud Drive.
///
/// Off the main actor, since reading a file in iCloud Drive can wait while it downloads.
nonisolated struct RecoveryCopyFiles: Sendable {
    let hiveID: UUID
    let directory: URL

    /// Every Hive's copy, each named for its Hive's ID.
    static var standardDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "Beekeeper", directoryHint: .isDirectory)
            .appending(path: "Recovery Files", directoryHint: .isDirectory)
    }

    static func standard(for hiveID: UUID) -> RecoveryCopyFiles {
        RecoveryCopyFiles(hiveID: hiveID, directory: standardDirectory)
    }

    private var copyURL: URL {
        directory.appending(path: "\(hiveID.uuidString).\(RecoveryFileHeader.fileExtension)", directoryHint: .notDirectory)
    }

    @concurrent
    func readCopy() async throws -> Data? {
        try Self.read(copyURL)
    }

    @concurrent
    func saveCopy(_ file: Data) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try file.write(to: copyURL, options: .atomic)
    }

    @concurrent
    func removeCopy() async throws {
        try Self.removeIfPresent(copyURL)
    }

    private static func read(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    private static func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }

    #if os(macOS)
    /// The folder the person chose for another copy, remembered with a bookmark so it's still found
    /// after it's moved or renamed.
    struct ChosenFolder: Codable, Equatable {
        var bookmark: Data
        /// The copy last written there, so the old one can be removed when the Hive is renamed.
        var fileName: String?
    }

    enum FolderError: Error {
        case notFound
    }

    private var folderRecordURL: URL {
        directory.appending(path: "\(hiveID.uuidString).folder.json", directoryHint: .notDirectory)
    }

    func loadFolder() throws -> ChosenFolder? {
        try Self.read(folderRecordURL).map { try JSONDecoder().decode(ChosenFolder.self, from: $0) }
    }

    func saveFolder(_ folder: ChosenFolder?) throws {
        guard let folder else {
            try Self.removeIfPresent(folderRecordURL)
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(folder).write(to: folderRecordURL, options: .atomic)
    }

    /// The folder's location, kept by a security-scoped bookmark since that also keeps the access the
    /// person gave by choosing it, such as to a folder in iCloud Drive.
    static func bookmark(for url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(options: .withSecurityScope)
    }

    /// Puts `copy` in the folder as `fileName`, or, without a copy, takes away one made with a key other
    /// than `currentKey`. Answers the folder's name, and the folder as it should be remembered from now on.
    @concurrent
    func updateFolderCopy(
        in folder: ChosenFolder,
        copy: Data?,
        currentKey: Data,
        fileName: String
    ) async throws -> (name: String, folder: ChosenFolder) {
        try Self.withFolder(folder) { url, folder in
            var updated = folder
            if let copy {
                let target = url.appending(path: fileName, directoryHint: .notDirectory)
                if try Self.read(target) != copy {
                    try copy.write(to: target, options: .atomic)
                }
                if let old = folder.fileName, old != fileName {
                    try Self.removeIfPresent(url.appending(path: old, directoryHint: .notDirectory))
                }
                updated.fileName = fileName
            } else {
                for name in Set([folder.fileName, fileName].compactMap(\.self)) {
                    let target = url.appending(path: name, directoryHint: .notDirectory)
                    if let existing = try Self.read(target), RecoveryFileHeader.publicKey(of: existing) != currentKey {
                        try FileManager.default.removeItem(at: target)
                    }
                }
            }
            return (FileManager.default.displayName(atPath: url.path(percentEncoded: false)), updated)
        }
    }

    @concurrent
    func removeFolderCopy(in folder: ChosenFolder) async throws {
        guard let fileName = folder.fileName else { return }
        try Self.withFolder(folder) { url, _ in
            try Self.removeIfPresent(url.appending(path: fileName, directoryHint: .notDirectory))
        }
    }

    @concurrent
    func folderName(of folder: ChosenFolder) async throws -> String {
        try Self.withFolder(folder) { url, _ in
            FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        }
    }

    /// Runs `body` with access to the folder, its bookmark made again when the old one has gone stale.
    private static func withFolder<Result>(
        _ folder: ChosenFolder,
        _ body: (URL, ChosenFolder) throws -> Result
    ) throws -> Result {
        var isStale = false
        let url = try URL(resolvingBookmarkData: folder.bookmark, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &isStale)
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else { throw FolderError.notFound }
        var current = folder
        if isStale, let renewed = try? url.bookmarkData(options: .withSecurityScope) {
            current.bookmark = renewed
        }
        return try body(url, current)
    }
    #endif
}
