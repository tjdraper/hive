import HiveKit
import SwiftUI

struct HiveOverviewView: View {
    let hive: KnownHive
    let link: HiveLink
    let servers: ServerList
    let onAddServer: () -> Void
    let onOpenSettings: () -> Void
    let onSelectServer: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let overview = link.overview, overview.fullDiskAccess != .granted {
                FullDiskAccessWarning(isOnThisMac: hive.isOnThisMac)
            }
            BackupDriveWarning(link: link, onOpenSettings: onOpenSettings)
            if servers.servers.isEmpty {
                ContentUnavailableView {
                    Label("No Servers Yet", systemImage: "server.rack")
                } description: {
                    Text("Add a server for this Hive to back up.")
                } actions: {
                    Button("Add Server…", action: onAddServer)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ServerOverviewList(servers: servers.servers, onSelect: onSelectServer)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await link.refresh()
            await servers.refresh()
        }
    }
}

private struct ServerOverviewList: View {
    let servers: [Server]
    let onSelect: (UUID) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(servers) { server in
                    Button { onSelect(server.id) } label: {
                        HStack {
                            Label(server.name, systemImage: "server.rack")
                            Spacer()
                            if server.isSetUp {
                                Text(server.connection.host)
                                    .foregroundStyle(.secondary)
                            } else {
                                Label("Not set up yet", systemImage: "exclamationmark.circle")
                                    .foregroundStyle(.orange)
                            }
                            Image(systemName: "chevron.forward")
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    if server.id != servers.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 4)
        } label: {
            Text("Servers")
        }
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
