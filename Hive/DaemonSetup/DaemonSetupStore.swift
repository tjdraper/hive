import Foundation
import Observation
import os
import ServiceManagement

@MainActor
@Observable
final class DaemonSetupStore {
    enum State {
        case checking
        case notInstalled
        case waitingForApproval
        case notRunning
        case running
        /// The plist isn't in the bundle, which only a broken build causes.
        case missingFromBundle
        /// The daemon refuses to start from a Hive.app that anyone but root can change.
        case notOwnedByRoot
    }

    /// A Debug Hive leaves registration to install-test-build.sh --mac, which runs its daemon as a user agent.
    #if DEBUG
    static let isDevelopmentBuild = true
    #else
    static let isDevelopmentBuild = false
    #endif

    private static let logger = Logger(subsystem: HiveAppLog.subsystem, category: "DaemonSetup")

    /// Scripts/write-launchd-plist.sh writes it into the bundle at build time.
    private static let plistName = "HiveDaemon.plist"

    private let service = SMAppService.daemon(plistName: plistName)
    private let plist = Bundle.main.bundleURL.appending(path: "Contents/Library/LaunchDaemons/\(plistName)", directoryHint: .notDirectory)

    private let daemonExecutable = Bundle.main.bundleURL.appending(path: "Contents/MacOS/HiveDaemon", directoryHint: .notDirectory)

    private(set) var state = State.checking
    private(set) var isRegistered = false
    private(set) var failureMessage: String?

    /// SMAppService doesn't announce changes, and approval happens in System Settings, so this polls while the window is open.
    func watch() async {
        while !Task.isCancelled {
            refresh()
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
        }
    }

    func refresh() {
        let isRunning = DaemonProcessFinder(executable: daemonExecutable).isRunning()
        if Self.isDevelopmentBuild {
            state = isRunning ? .running : .notRunning
            return
        }

        let status = service.status
        isRegistered = status == .enabled || status == .requiresApproval
        guard isOwnedByRoot() else {
            state = .notOwnedByRoot
            return
        }

        state = switch status {
        case .notRegistered: .notInstalled
        case .requiresApproval: .waitingForApproval
        case .enabled: isRunning ? .running : .notRunning
        // SMAppService also reports a daemon that was never registered as not found.
        case .notFound: FileManager.default.fileExists(atPath: plist.path(percentEncoded: false)) ? .notInstalled : .missingFromBundle
        @unknown default: .missingFromBundle
        }
    }

    /// The daemon checks every file in the bundle when it starts. The top folder is enough to tell an
    /// install made by an administrator from one dragged in by the user.
    private func isOwnedByRoot() -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: Bundle.main.bundlePath),
              let owner = attributes[.ownerAccountID] as? NSNumber
        else { return false }
        return owner.intValue == 0
    }

    func install() {
        failureMessage = nil
        do {
            try service.register()
            Self.logger.info("Registered the daemon")
        } catch {
            // Registering a daemon for the first time reports an error while it waits for approval.
            if service.status != .requiresApproval {
                Self.logger.error("Registering the daemon failed: \(error.localizedDescription, privacy: .public)")
                failureMessage = error.localizedDescription
            }
        }
        refresh()
        if state == .waitingForApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func remove() async {
        failureMessage = nil
        do {
            try await service.unregister()
            Self.logger.info("Unregistered the daemon")
        } catch {
            Self.logger.error("Unregistering the daemon failed: \(error.localizedDescription, privacy: .public)")
            failureMessage = error.localizedDescription
        }
        refresh()
    }
}
