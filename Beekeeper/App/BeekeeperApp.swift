import os
import SwiftUI

@main
struct BeekeeperApp: App {
    init() {
        Logger(subsystem: BeekeeperLog.subsystem, category: "Launch").info("Beekeeper launched")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if os(macOS)
                LocalHiveView()
                #else
                Color.clear
                #endif
            }
            .frame(minWidth: 480, minHeight: 320)
        }
    }
}
