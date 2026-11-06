import Foundation
import HiveKit
import os

/// A Hive this device has paired with, as the list of Hives keeps it. What it needs to trust the Hive,
/// the pin and its own key, is in the keychain (`DeviceCredential`).
struct KnownHive: Codable, Hashable, Identifiable {
    let id: UUID
    /// As last seen, so the list reads right while the Hive is offline.
    var name: String
    var addresses: [HiveAddress]
    /// Paired over XPC as Beekeeper on the Hive Mac, which can pair again the same way.
    let isOnThisMac: Bool
}

/// The list of Hives in a small file of Beekeeper's own, never synced: each device pairs on its own.
struct HiveListFile {
    private static let logger = Logger(subsystem: BeekeeperLog.subsystem, category: "HiveList")

    let url: URL

    static var standard: HiveListFile {
        let folder = URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "Beekeeper", directoryHint: .isDirectory)
        return HiveListFile(url: folder.appending(path: "Hives.json", directoryHint: .notDirectory))
    }

    func load() -> [KnownHive] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            Self.logger.error("Couldn't read the list of Hives: \(String(describing: error), privacy: .public)")
            return []
        }

        do {
            return try JSONDecoder().decode([KnownHive].self, from: data)
        } catch {
            // Set aside rather than overwritten at the next save, so it can still be looked at.
            Self.logger.error("The list of Hives is unreadable, setting it aside")
            let aside = url.deletingPathExtension().appendingPathExtension("unreadable.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            return []
        }
    }

    func save(_ hives: [KnownHive]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(hives).write(to: url, options: .atomic)
        } catch {
            Self.logger.error("Couldn't save the list of Hives: \(String(describing: error), privacy: .public)")
        }
    }
}
