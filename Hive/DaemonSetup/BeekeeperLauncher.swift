import AppKit

@MainActor
struct BeekeeperLauncher {
    /// Beekeeper's bundle ID is built from the same prefix as Hive's (Configuration/Signing.xcconfig), and
    /// a Debug build's ends in `.Debug` like Hive's.
    private static var beekeeperBundleID: String? {
        guard let hiveBundleID = Bundle.main.bundleIdentifier else { return nil }
        let suffixes = [(hive: ".Hive.Debug", beekeeper: ".HiveBeekeeper.Debug"), (hive: ".Hive", beekeeper: ".HiveBeekeeper")]
        for suffix in suffixes where hiveBundleID.hasSuffix(suffix.hive) {
            return hiveBundleID.dropLast(suffix.hive.count) + suffix.beekeeper
        }
        return nil
    }

    /// Prefers the copy beside this Hive, so a Debug Hive opens the Debug Beekeeper built with it.
    var applicationURL: URL? {
        guard let bundleID = Self.beekeeperBundleID else { return nil }
        let copies = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
        let hiveFolder = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL
        return copies.first { $0.deletingLastPathComponent().standardizedFileURL == hiveFolder } ?? copies.first
    }

    func open() {
        guard let applicationURL else { return }
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
