import os
import SwiftUI

@main
struct BeekeeperApp: App {
    @State private var hives = HiveListStore()

    init() {
        Logger(subsystem: BeekeeperLog.subsystem, category: "Launch").info("Beekeeper launched")
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(hives)
        }
        .defaultSize(width: 960, height: 620)

        #if os(macOS) && (DEBUG || TEST_BUILD)
        // Never in a released build. It signs in as this device like everything else and gets no extra access.
        Window("Developer", id: DeveloperWindow.id) {
            DeveloperWindow()
                .environment(hives)
        }
        .defaultSize(width: 720, height: 560)
        #endif
    }
}
