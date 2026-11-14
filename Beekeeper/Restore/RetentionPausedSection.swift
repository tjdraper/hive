import HiveKit
import SwiftUI

/// On the overview after a restore, or after Hive took over snapshots from a backup drive: what it took
/// over, and the space each server uses against its quota. Retention and quotas remove nothing until
/// they're started again here (§10), since a drive restored from a Mac backup may have lost its hard
/// links and take more space than it did.
struct RetentionPausedSection: View {
    let hive: KnownHive
    let link: HiveLink
    let state: RestoreState
    let onStarted: () -> Void

    @State private var isAsking = false
    @State private var isStarting = false
    @State private var failure: String?

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Retention and quotas are waiting")
                        .font(.headline)
                    Text(
                        "Hive took over these snapshots from the backup drive. It removes none of them until you start "
                            + "retention and quotas again. Backups run as usual meanwhile."
                    )
                    .foregroundStyle(.secondary)
                }
            }
            ForEach(state.servers) { server in
                ServerTakenOver(server: server)
            }
            if let failure {
                Text(failure)
                    .foregroundStyle(.red)
            }
            Button("Start Retention and Quotas…") { isAsking = true }
                .disabled(isStarting)
        }
        .confirmationDialog("Start retention and quotas for “\(hive.name)”?", isPresented: $isAsking) {
            Button("Start Retention and Quotas") { Task { await start() } }
        } message: {
            Text(message)
        }
    }

    private var message: String {
        let over = state.servers.filter { server in
            guard let quota = server.quotaBytes, let used = server.usedBytes else { return false }
            return used > quota
        }
        let base = "Hive removes the snapshots each job's tiers don't keep, and brings each server within its quota."
        guard !over.isEmpty else { return base }
        let names = over.map { "“\($0.name)”" }.formatted(.list(type: .and))
        return base + " \(names) uses more than its quota, so its oldest daily snapshots go first."
    }

    private func start() async {
        isStarting = true
        defer { isStarting = false }
        do {
            try await link.confirmed(
                "DELETE",
                HiveEndpoint.retentionPause,
                reason: "start retention and quotas for “\(hive.name)”, which removes snapshots"
            )
            failure = nil
            onStarted()
        } catch ConfirmationKeyError.cancelled {
            return
        } catch {
            failure = HiveLink.message(for: error)
        }
    }
}

private struct ServerTakenOver: View {
    let server: RestoredServer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(server.name, systemImage: "server.rack")
                Spacer()
                Text(space)
                    .foregroundStyle(isOverQuota ? .orange : .secondary)
            }
            ForEach(server.jobs) { job in
                HStack {
                    Text(job.name)
                    Spacer()
                    Text(job.snapshotCount == 1 ? "1 snapshot" : "\(job.snapshotCount) snapshots")
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 24)
            }
        }
    }

    private var isOverQuota: Bool {
        guard let quota = server.quotaBytes, let used = server.usedBytes else { return false }
        return used > quota
    }

    private var space: String {
        guard let used = server.usedBytes else { return "Counting…" }
        let usedText = used.formatted(.byteCount(style: .file))
        guard let quota = server.quotaBytes else { return usedText }
        return "\(usedText) of \(quota.formatted(.byteCount(style: .file)))"
    }
}
