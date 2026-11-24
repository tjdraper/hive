import HiveKit
import SwiftUI

/// Whether a server's Scout reports, what it last said about the server, and adding, updating and
/// removing it: over SSH where Hive can run Scout's management command as root, and otherwise with the
/// command to run on the server.
struct ServerMetricsSection: View {
    let link: HiveLink
    let server: Server

    /// Often enough that the last report stays close to the truth.
    private static let refreshInterval = Duration.seconds(15)
    /// Beekeeper warns past this (§5).
    private static let largestClockOffset = 60

    @Environment(\.presentFormSheet) private var presentSheet
    @State private var state: ServerMetricsState?
    @State private var failure: String?
    @State private var isConfirmingRemoval = false
    @State private var removalFailure: String?
    /// Shown once metrics are removed, until the page closes.
    @State private var showsUninstall = false
    @State private var platform = ScoutRelease.Platform.x86
    @State private var ssh: ScoutOverSSH?
    @State private var isConfirmingUninstall = false

    var body: some View {
        Section {
            if let state {
                rows(state)
            } else if let failure {
                Text(failure)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        } header: {
            Text("Metrics")
        }
        .task(id: server.id) {
            let ssh = ScoutOverSSH(link: link, server: server)
            self.ssh = ssh
            Task { await ssh.refresh() }
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
        .confirmationDialog("Remove Metrics from “\(server.name)”?", isPresented: $isConfirmingRemoval) {
            Button("Remove Metrics", role: .destructive) { Task { await removeMetrics() } }
        } message: {
            Text("Hive stops accepting its Scout's figures at once. Those already kept stay until they age out.")
        }
        .confirmationDialog("Uninstall Scout from “\(server.name)”?", isPresented: $isConfirmingUninstall) {
            Button("Uninstall Scout", role: .destructive) { Task { await run(.uninstall) } }
        } message: {
            Text(
                "Hive removes Scout, its service and its rule from the server, and stops accepting its figures. "
                    + "Those already kept stay until they age out."
            )
        }
        .alert("Couldn't Remove Metrics", isPresented: isFailingRemoval) {
            Button("OK") { removalFailure = nil }
        } message: {
            Text(removalFailure ?? "")
        }
    }

    @ViewBuilder private func rows(_ state: ServerMetricsState) -> some View {
        if let scout = state.scout {
            reporting(scout)
        } else if state.hasMetrics {
            Label(
                "This server's Scout has to enroll again, since the Hive was restored or took a new identity. "
                    + "Until then Hive refuses its figures.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
            Button("Enroll Scout Again…", systemImage: "arrow.clockwise") { addMetrics(previous: nil) }
            removal
        } else {
            Text("Scout isn't reporting this server's CPU, memory, disks and network to the Hive.")
                .foregroundStyle(.secondary)
            Button("Add Metrics…", systemImage: "plus") { addMetrics(previous: nil) }
            if ssh?.canManage == true {
                // Installed, such as after its metrics were removed, so Hive can take it off.
                Button("Uninstall Scout…", systemImage: "trash", role: .destructive) { isConfirmingUninstall = true }
                    .disabled(ssh?.working != nil)
            } else if showsUninstall {
                uninstall
            }
        }
        if let ssh {
            ScoutActionStatus(ssh: ssh, server: server)
        }
    }

    /// Uninstalling over SSH removes the metrics too, so it takes Remove Metrics' place where Hive can.
    @ViewBuilder private var removal: some View {
        if ssh?.canManage == true {
            Button("Uninstall Scout…", systemImage: "trash", role: .destructive) { isConfirmingUninstall = true }
                .disabled(ssh?.working != nil)
        } else {
            Button("Remove Metrics…", systemImage: "trash", role: .destructive) { isConfirmingRemoval = true }
        }
    }

    @ViewBuilder private func reporting(_ scout: ScoutState) -> some View {
        LabeledContent("Last report") {
            if let lastReport = scout.lastReportAt {
                Text(lastReport, format: .relative(presentation: .named))
            } else {
                Text("None yet")
            }
        }
        if let refusal = scout.lastRefusal {
            Label(Self.refusalMessage(refusal), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        LabeledContent("Scout", value: [scout.version, scout.platform].compactMap(\.self).joined(separator: ", "))
        if let update = scout.update {
            updateRows(update, platform: scout.platform)
        }
        if let distribution = scout.distribution {
            LabeledContent("System", value: distribution)
        }
        if let kernel = scout.kernel {
            LabeledContent("Kernel", value: kernel)
        }
        if let offset = scout.clockOffsetSeconds {
            LabeledContent("Clock", value: Self.clockDescription(offset))
            if abs(offset) > Self.largestClockOffset {
                Label(
                    "The server's clock is more than a minute off. Its figures show at the wrong times.",
                    systemImage: "clock.badge.exclamationmark"
                )
                .foregroundStyle(.orange)
            }
        }
        if scout.processesHidden == true {
            Text("The server hides other users' processes from Scout, so it reports none.")
                .foregroundStyle(.secondary)
        }
        LabeledContent("Enrolled", value: scout.enrolledAt.formatted(date: .abbreviated, time: .shortened))
        Button("Enroll Scout Again…", systemImage: "arrow.clockwise") { addMetrics(previous: scout) }
        if ssh?.canManage == true {
            Button("Give Scout the Hive's Addresses", systemImage: "network") { Task { await run(.sendAddresses) } }
                .disabled(ssh?.working != nil)
                .help("For when the Hive's addresses for other devices have changed, so Scout needn't enroll again")
        }
        removal
    }

    @ViewBuilder private func updateRows(_ update: ScoutUpdate, platform reported: String?) -> some View {
        switch update {
        case .newerRelease(let version):
            Label("Scout \(version) is available.", systemImage: "arrow.down.circle")
                .foregroundStyle(.orange)
        case .protocolNotAccepted:
            Label(
                "This Hive no longer accepts what this Scout sends. Update it to report again.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
        }
        if ssh?.canManage == true {
            Button("Update Scout", systemImage: "arrow.down.circle") { Task { await run(.update) } }
                .disabled(ssh?.working != nil)
        } else if let release = ThisBuildsScout.release {
            VStack(alignment: .leading, spacing: 8) {
                Text("Run this as root on the server to update Scout to \(release.version), keeping its enrollment.")
                PlatformCommand(platform: $platform) { ScoutCommand.update(release, for: $0) }
            }
            .task(id: reported) { platform = ThisBuildsScout.platform(reportedAs: reported) ?? platform }
        } else {
            Text("This build of Beekeeper has no address to download Scout from. Use Scripts/scout-test-vm.sh.")
                .foregroundStyle(.secondary)
        }
    }

    private var uninstall: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To take Scout off the server, run this there as root.")
            CommandBox(text: ScoutCommand.uninstall)
        }
    }

    private var isFailingRemoval: Binding<Bool> {
        Binding { removalFailure != nil } set: { if !$0 { removalFailure = nil } }
    }

    private func addMetrics(previous: ScoutState?) {
        presentSheet? {
            AddMetricsSheet(
                link: link,
                server: server,
                previousEnrollment: previous?.enrolledAt,
                reportedPlatform: previous?.platform
            ) {
                showsUninstall = false
                Task {
                    await load()
                    await ssh?.refresh()
                }
            }
        }
    }

    private func run(_ action: ScoutAction) async {
        guard let ssh else { return }
        await ssh.perform(action)
        if action == .uninstall, ssh.outcome?.succeeded == true { showsUninstall = false }
        await load()
    }

    private func load() async {
        do {
            state = try await link.perform { try await $0.get(HiveEndpoint.metrics(ofServer: server.id)) }
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            if state == nil { failure = HiveLink.message(for: error) }
        }
    }

    private func removeMetrics() async {
        do {
            try await link.perform { try await $0.delete(HiveEndpoint.metrics(ofServer: server.id)) }
            showsUninstall = true
            await load()
        } catch {
            removalFailure = HiveLink.message(for: error)
        }
    }

    private static func clockDescription(_ offset: Int) -> String {
        if abs(offset) < 2 { return "In step with the Hive" }
        let amount = Duration.seconds(abs(offset)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
        return offset > 0 ? "\(amount) ahead of the Hive" : "\(amount) behind the Hive"
    }

    private static func refusalMessage(_ refusal: String) -> String {
        switch refusal {
        case "clock-ahead": "The server's clock is too far ahead, so Hive refuses its figures."
        case "too-old": "Hive refused its last figures as more than a day old."
        default: "Hive refused its last figures (\(refusal))."
        }
    }
}
