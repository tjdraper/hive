import Foundation
import HiveKit

/// The recovery files Beekeeper already keeps, one for each Hive it has known (F2), offered first when
/// restoring, since a Mac that managed a Hive before has its latest file.
nonisolated struct StoredRecoveryFile: Identifiable, Hashable, Sendable {
    let url: URL
    let hiveID: UUID?
    let modified: Date

    var id: URL {
        url
    }

    /// Off the main actor, since the folder may hold copies of several Hives' files.
    @concurrent
    static func all(in directory: URL = RecoveryCopyFiles.standardDirectory) async -> [StoredRecoveryFile] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )) ?? []
        return urls
            .filter { $0.pathExtension == RecoveryFileHeader.fileExtension }
            .map { url in
                StoredRecoveryFile(
                    url: url,
                    hiveID: UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                    modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                )
            }
            .sorted { $0.modified > $1.modified }
    }
}
