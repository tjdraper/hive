import HiveKit
import SwiftUI

struct HiveOverviewView: View {
    let hive: KnownHive
    let link: HiveLink

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let overview = link.overview, overview.fullDiskAccess != .granted {
                FullDiskAccessWarning(isOnThisMac: hive.isOnThisMac)
            }
            ContentUnavailableView(
                "No Servers Yet",
                systemImage: "server.rack",
                description: Text("Servers this Hive backs up will appear here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await link.refresh() }
    }
}

/// A daemon can't ask for Full Disk Access, so the warning stays until it's turned on.
private struct FullDiskAccessWarning: View {
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")

    let isOnThisMac: Bool

    @Environment(\.openURL) private var openURL

    var body: some View {
        GroupBox {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hive doesn't have Full Disk Access")
                        .font(.headline)
                    Text(
                        "It can't write backups until Full Disk Access is turned on for “Hive” "
                            + "in System Settings › Privacy & Security on the Hive's Mac."
                    )
                        .foregroundStyle(.secondary)
                    #if os(macOS)
                    if isOnThisMac, let url = Self.settingsURL {
                        Button("Open Full Disk Access Settings") { openURL(url) }
                    }
                    #endif
                }
                Spacer(minLength: 0)
            }
            .padding(4)
        }
    }
}
