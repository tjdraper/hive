#if os(macOS)
import AppKit

final class BeekeeperAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        #if !DEBUG
        Task { await MoveToApplicationsWorkflow.offerIfNeeded() }
        #endif
    }
}
#endif
