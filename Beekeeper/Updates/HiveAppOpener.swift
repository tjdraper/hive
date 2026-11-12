#if os(macOS)
import AppKit

/// Opens Hive.app on this Mac, which checks for its own update as it opens.
struct HiveAppOpener {
    /// Prefers the copy beside this Beekeeper, so a Debug Beekeeper opens the Debug Hive built with it.
    var applicationURL: URL? {
        guard let bundleID = Bundle.main.object(forInfoDictionaryKey: "HiveBundleIdentifier") as? String, !bundleID.isEmpty else {
            return nil
        }
        let copies = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
        let beekeeperFolder = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL
        return copies.first { $0.deletingLastPathComponent().standardizedFileURL == beekeeperFolder } ?? copies.first
    }

    func open() {
        guard let applicationURL else { return }
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
#endif
