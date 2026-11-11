import HiveKit
import SwiftUI

struct HiveOverviewView: View {
    let hive: KnownHive
    let link: HiveLink
    let servers: ServerList
    let recovery: RecoveryFileCopies
    let onAddServer: () -> Void
    let onOpenSettings: () -> Void
    let onSelectServer: (UUID) -> Void

    @Environment(HiveListStore.self) private var store
    @State private var isSettingUpRecoveryKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let overview = link.overview, overview.fullDiskAccess != .granted {
                FullDiskAccessWarning(isOnThisMac: hive.isOnThisMac)
            }
            if let state = recovery.hiveState, !state.hasKey {
                RecoveryKeyWarning { isSettingUpRecoveryKey = true }
            }
            BackupDriveWarning(link: link, onOpenSettings: onOpenSettings)
            if case .afterIdle(let minutes) = link.overview?.macSleep {
                MacSleepWarning(minutes: minutes, isOnThisMac: hive.isOnThisMac)
            }
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
                ServerOverviewList(servers: servers, onSelect: onSelectServer)
            }
            if recovery.hiveState?.hasKey == true {
                RecoveryFileSummary(copies: recovery)
            }
            RemovedJobsSection(hive: hive, link: link, statuses: servers.statuses)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $isSettingUpRecoveryKey) {
            RecoveryKeySheet(hiveName: hive.name, link: link) { recovery.receive($0) }
        }
        .task {
            await link.refresh()
            await loadRecoveryKey()
            await servers.refresh()
        }
    }

    /// A Hive just paired goes on to its recovery key, since its setup isn't finished without one.
    private func loadRecoveryKey() async {
        await recovery.refresh()
        if store.takeNewlyPaired(hive.id), recovery.hiveState?.hasKey == false {
            isSettingUpRecoveryKey = true
        }
    }
}

private struct ServerOverviewList: View {
    let servers: ServerList
    let onSelect: (UUID) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(servers.servers) { server in
                    Button { onSelect(server.id) } label: {
                        HStack {
                            Label(server.name, systemImage: "server.rack")
                            Spacer()
                            if server.isSetUp {
                                ServerHealthLabel(jobs: servers.jobs.jobs(onServer: server.id), statuses: servers.statuses)
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
                    if server.id != servers.servers.last?.id {
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

/// The server's most pressing job status, or when it was last backed up.
private struct ServerHealthLabel: View {
    let jobs: [BackupJob]
    let statuses: JobStatusStore

    var body: some View {
        let health = JobHealth(jobs: jobs, in: statuses)
        HStack(spacing: 6) {
            JobHealthBadge(health: health)
            if jobs.isEmpty {
                Text("No backup jobs")
            } else if health == .fine, let last = lastSnapshot {
                // Each minute, and without seconds, so it never sits on a stale "47 seconds ago".
                TimelineView(.everyMinute) { _ in
                    Text("Backed up \(last.formatted(Self.ago))")
                }
                .help(last.spoken)
            } else {
                Text(health.label)
            }
        }
        .foregroundStyle(.secondary)
    }

    private static var ago: Date.RelativeFormatStyle {
        var style = Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide)
        style.allowedFields = [.year, .month, .week, .day, .hour, .minute]
        return style
    }

    /// The oldest of its jobs' last snapshots, since the server is only as backed up as that.
    private var lastSnapshot: Date? {
        let dates = jobs.map { statuses.status(of: $0.id)?.lastSnapshotAt }
        guard !dates.contains(nil) else { return nil }
        return dates.compactMap(\.self).min()
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
