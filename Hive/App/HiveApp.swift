import SwiftUI

@main
struct HiveApp: App {
    var body: some Scene {
        Window("Hive", id: "status") {
            DaemonSetupView()
        }
        .windowResizability(.contentSize)
    }
}
