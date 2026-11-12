import SwiftUI

struct UpdatesSection: View {
    let updater: HiveUpdater

    var body: some View {
        Section("Updates") {
            LabeledContent("Version", value: updater.version)
            if updater.updatesItself {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            } else {
                Text("This copy of Hive doesn't update itself.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
