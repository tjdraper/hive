import HiveKit
import SwiftUI

struct HiveOverviewView: View {
    let hive: KnownHive
    let link: HiveLink
    let servers: ServerList
    let recovery: RecoveryFileCopies
    let onAddServer: () -> Void
    let onOpenSettings: () -> Void
    /// Rows for the Hive's other pages at the end, where they aren't tabs.
    let onOpenPage: ((HivePage) -> Void)?
    let onSelectServer: (UUID) -> Void
    let onRestored: (RestoreOutcome) -> Void

    private enum SetupSheet: Identifiable {
        case choice
        case recoveryKey
        case restore

        var id: Self {
            self
        }
    }

    @Environment(HiveListStore.self) private var store
    @State private var setupSheet: SetupSheet?
    @State private var restoreState: RestoreState?
    @State private var drive = BackupDriveWatch()
    @State private var removedJobs = RemovedJobList()
    /// Handed on once the sheet has closed. The restored Hive takes this one's place in the list, and
    /// removing the view a sheet came from while it closes leaves the window drawing nothing.
    @State private var restored: RestoreOutcome?

    var body: some View {
        Form {
            if let overview = link.overview, overview.fullDiskAccess != .granted {
                FullDiskAccessWarning(isOnThisMac: hive.isOnThisMac)
            }
            if let hiveVersion = link.overview?.version, let beekeeperVersion = HiveUpdateNotice.beekeeperVersion,
               hiveVersion < beekeeperVersion {
                HiveUpdateNotice(hiveVersion: hiveVersion, beekeeperVersion: beekeeperVersion, isOnThisMac: hive.isOnThisMac)
            }
            if let state = recovery.hiveState, !state.hasKey {
                RecoveryKeyWarning(
                    onSetUp: { setupSheet = .recoveryKey },
                    onRestore: canRestore ? { setupSheet = .restore } : nil
                )
            }
            if let restoreState, restoreState.retentionPausedSince != nil {
                RetentionPausedSection(hive: hive, link: link, state: restoreState) {
                    Task { await loadRestoreState() }
                }
            }
            BackupDriveWarning(state: drive.state, onOpenSettings: onOpenSettings)
            if case .afterIdle(let minutes) = link.overview?.macSleep {
                MacSleepWarning(minutes: minutes, isOnThisMac: hive.isOnThisMac)
            }
            ServerOverviewList(servers: servers, onAddServer: onAddServer, onSelect: onSelectServer)
            if recovery.hiveState?.hasKey == true {
                RecoveryFileSummary(copies: recovery)
            }
            RemovedJobsSection(hive: hive, link: link, statuses: servers.statuses, removed: removedJobs)
            if let onOpenPage {
                HivePageLinks(onOpen: onOpenPage)
            }
        }
        .formStyle(.grouped)
        .hostsFormSheets()
        .sheet(item: $setupSheet, onDismiss: handOnRestore) { sheet in
            switch sheet {
            case .choice:
                HiveSetupSheet(hive: hive, link: link, onKeySaved: { recovery.receive($0) }, onRestored: { restored = $0 })
            case .recoveryKey:
                RecoveryKeySheet(hiveName: hive.name, link: link) { recovery.receive($0) }
            case .restore:
                RestoreSheet(hive: hive, link: link) { restored = $0 }
            }
        }
        .task {
            await link.refresh()
            await loadRestoreState()
            await loadRecoveryKey()
            await servers.refresh()
        }
        .task { await drive.watch(link) }
        .task(id: servers.statuses.logRevision) { await removedJobs.load(link) }
    }

    private func handOnRestore() {
        guard let restored else { return }
        self.restored = nil
        onRestored(restored)
    }

    /// Only Beekeeper on the Hive's own Mac can restore it, and only while it has no configuration.
    private var canRestore: Bool {
        hive.isOnThisMac && restoreState?.canRestore == true
    }

    /// A Hive just paired goes on to its setup, since it isn't finished without a recovery key. One on this
    /// Mac with nothing set up yet could instead be a Hive brought back from its recovery file.
    private func loadRecoveryKey() async {
        await recovery.refresh()
        if store.takeNewlyPaired(hive.id), recovery.hiveState?.hasKey == false {
            setupSheet = canRestore ? .choice : .recoveryKey
        }
    }

    private func loadRestoreState() async {
        if let loaded: RestoreState = try? await link.perform({ try await $0.get(HiveEndpoint.restore) }) {
            restoreState = loaded
        }
    }
}

private struct ServerOverviewList: View {
    let servers: ServerList
    let onAddServer: () -> Void
    let onSelect: (UUID) -> Void

    var body: some View {
        Section("Servers") {
            if servers.servers.isEmpty {
                Text("No servers yet. Add one for this Hive to back up.")
                    .foregroundStyle(.secondary)
                Button("Add Server…", systemImage: "plus", action: onAddServer)
            }
            ForEach(servers.servers) { server in
                Button { onSelect(server.id) } label: {
                    HStack {
                        #if os(macOS)
                        Label(server.name, systemImage: "server.rack")
                        Spacer()
                        status(of: server)
                        #else
                        // Under the name, as a long name beside it would leave both wrapping at iPhone width.
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name)
                                status(of: server)
                                    .font(.subheadline)
                            }
                        } icon: {
                            Image(systemName: "server.rack")
                        }
                        Spacer(minLength: 0)
                        #endif
                        Image(systemName: "chevron.forward")
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func status(of server: Server) -> some View {
        if server.isSetUp {
            ServerHealthLabel(jobs: servers.jobs.jobs(onServer: server.id), statuses: servers.statuses)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                Text("Not set up yet")
            }
            .foregroundStyle(.orange)
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
        Section {
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
                }
            }
            #if os(macOS)
            if isOnThisMac, let url = Self.settingsURL {
                Button("Open Full Disk Access Settings") { openURL(url) }
            }
            #endif
        }
    }
}
