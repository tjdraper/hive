#if os(macOS)
import Foundation
import Observation
import os
import Sparkle

/// Beekeeper on the Mac updates itself. iPhone and iPad builds come through TestFlight instead.
@Observable
final class BeekeeperUpdater {
    private static let logger = Logger(subsystem: BeekeeperLog.subsystem, category: "Updates")

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var readiness: NSKeyValueObservation?

    private(set) var canCheckForUpdates = false

    var updatesItself: Bool {
        controller != nil
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
#endif
