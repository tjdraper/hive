import HiveKit
import SwiftUI

/// Hive keeps its Mac awake while a backup runs, but can't wake it for one that's due.
struct MacSleepWarning: View {
    /// One pane serves both Energy, on a desktop Mac, and Battery, on a laptop.
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")

    let minutes: Int
    let isOnThisMac: Bool

    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 8) {
                    Text("The Hive's Mac sleeps after \(minutes) \(minutes == 1 ? "minute" : "minutes") idle")
                        .font(.headline)
                    Text(
                        "A backup due while it sleeps runs late, once it wakes. To run backups on time, stop it sleeping "
                            + "automatically in System Settings › Energy, or Battery on a laptop."
                    )
                    .foregroundStyle(.secondary)
                }
            }
            #if os(macOS)
            if isOnThisMac, let url = Self.settingsURL {
                Button("Open Energy Settings") { openURL(url) }
            }
            #endif
        }
    }
}
