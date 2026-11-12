import Foundation
import Observation
import os
import Sparkle

/// Updates Hive.app, and with it the daemon inside. Only root can change Hive.app, so Sparkle asks for an
/// administrator password and gives the new copy the old one's owner. The daemon notices its executable
/// was replaced and restarts on the new version.
@MainActor
@Observable
final class HiveUpdater {
    private static let logger = Logger(subsystem: HiveAppLog.subsystem, category: "Updates")

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var readiness: NSKeyValueObservation?

    private(set) var canCheckForUpdates = false

    var updatesItself: Bool {
        controller != nil
    }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    init() {
        guard Self.isFeedConfigured else {
            controller = nil
            Self.logger.info("This build doesn't update itself")
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        readiness = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            // Sparkle changes it on the main thread, so the observer runs there too.
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
        // Hive.app is only open now and then, such as when Beekeeper opens it to update, so a daily
        // scheduled check would rarely be due while it's open.
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Debug builds have their own bundle ID, and a copy built without a feed in
    /// Configuration/Signing.local.xcconfig is left to whoever built it.
    private static var isFeedConfigured: Bool {
        #if DEBUG
        return false
        #else
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let feed = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String).flatMap(URL.init(string:))
        return !key.isEmpty && feed?.host()?.isEmpty == false
        #endif
    }
}
