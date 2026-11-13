#if os(macOS)
import AppKit
import HiveKit
import os

/// Sparkle can't replace a Beekeeper running from Downloads, since macOS runs it from a read-only copy
/// there, so a released Beekeeper opened outside an Applications folder offers to move itself.
enum MoveToApplicationsWorkflow {
    private static let logger = Logger(subsystem: BeekeeperLog.subsystem, category: "Install")
    private static let declinedKey = "MoveToApplicationsDeclined"

    static func offerIfNeeded() async {
        let running = Bundle.main.bundleURL
        let location = TranslocationResolver.locate(running)
        let realLocation: URL? = switch location {
        case let .inPlace(url): url
        case let .translocated(original): original
        }
        if let realLocation, isInApplicationsFolder(realLocation) { return }
        guard !UserDefaults.standard.bool(forKey: declinedKey) else { return }

        let destination = URL(filePath: "/Applications", directoryHint: .isDirectory)
            .appending(path: running.lastPathComponent)
        let installed = Bundle(url: destination)

        if let installed, installed.bundleIdentifier != Bundle.main.bundleIdentifier {
            logger.info("Not offering to move: another app has Beekeeper's name in Applications")
            return
        }

        if let installed, let current = version(of: .main), let installedVersion = version(of: installed),
           installedVersion >= current {
            guard ask(
                "Beekeeper is already in the Applications folder",
                "Open that copy and move this one to the Trash?",
                confirm: "Open the Copy in Applications"
            ) else { return }
            await relaunch(from: destination, removing: realLocation)
            return
        }

        guard ask(
            "Move Beekeeper to the Applications folder?",
            installed == nil
                ? "Beekeeper can only update itself from the Applications folder."
                : "Beekeeper can only update itself from the Applications folder. The older copy there is replaced.",
            confirm: "Move to Applications Folder"
        ) else { return }

        do {
            try copy(running, to: destination)
        } catch {
            logger.error("Couldn't move to Applications: \(String(describing: type(of: error)), privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Beekeeper couldn't move itself"
            alert.informativeText = "\(error.localizedDescription) Drag Beekeeper to the Applications folder in Finder instead."
            alert.runModal()
            return
        }
        logger.info("Moved to Applications")
        await relaunch(from: destination, removing: realLocation)
    }

    private static func isInApplicationsFolder(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/")
    }

    /// macOS reports a running app's bundle URL with a trailing slash, which makes equal URLs compare unequal.
    private static func isSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().path == rhs.resolvingSymlinksInPath().path
    }

    private static func version(of bundle: Bundle) -> ReleaseVersion? {
        (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(ReleaseVersion.init)
    }

    /// Returns whether the user confirmed. Declining is remembered, so Beekeeper asks only once.
    private static func ask(_ message: String, _ information: String, confirm: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = information
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if !confirmed, alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: declinedKey)
        }
        return confirmed
    }

    /// Copies beside the destination first, so a failed copy never costs the copy already installed.
    private static func copy(_ bundle: URL, to destination: URL) throws {
        let files = FileManager.default
        let staging = try files.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true
        )
        defer { try? files.removeItem(at: staging) }
        let copy = staging.appending(path: destination.lastPathComponent)
        try files.copyItem(at: bundle, to: copy)
        removeQuarantine(from: copy)
        if files.fileExists(atPath: destination.path) {
            _ = try files.replaceItemAt(destination, withItemAt: copy)
        } else {
            try files.moveItem(at: copy, to: destination)
        }
    }

    /// A quarantined copy that wasn't moved in Finder is translocated again at its next launch. Gatekeeper
    /// already checked this signed, notarized copy when it was first opened, as LetsMove relies on too.
    private static func removeQuarantine(from bundle: URL) {
        let paths = [bundle.path] + (FileManager.default.subpaths(atPath: bundle.path) ?? [])
            .map { bundle.appending(path: $0).path }
        for path in paths {
            removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }

    private static func relaunch(from destination: URL, removing original: URL?) async {
        let alreadyRunning = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).first { $0 != .current && $0.bundleURL.map { isSameFile($0, destination) } == true }

        if let alreadyRunning {
            alreadyRunning.activate()
        } else {
            // This copy shares its bundle ID, so macOS may bring it forward instead of opening the one in Applications.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            do {
                _ = try await NSWorkspace.shared.openApplication(at: destination, configuration: configuration)
            } catch {
                logger.error("Couldn't open the copy in Applications: \(String(describing: type(of: error)), privacy: .public)")
                return
            }
        }
        if let original, !isSameFile(original, destination) {
            try? FileManager.default.trashItem(at: original, resultingItemURL: nil)
        }
        NSApp.terminate(nil)
    }
}
#endif
