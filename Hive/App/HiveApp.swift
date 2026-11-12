import SwiftUI

@main
struct HiveApp: App {
    @State private var updater = HiveUpdater()

    var body: some Scene {
        Window("Hive", id: "status") {
            DaemonSetupView(updater: updater)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                if updater.updatesItself {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            }
        }
    }
}
