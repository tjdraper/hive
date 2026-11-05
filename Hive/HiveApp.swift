import SwiftUI

@main
struct HiveApp: App {
    var body: some Scene {
        Window("Hive", id: "status") {
            Color.clear
                .frame(minWidth: 360, minHeight: 200)
        }
        .windowResizability(.contentSize)
    }
}
