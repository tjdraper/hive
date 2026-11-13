import HiveKit
import SwiftUI

/// Snapshots that stayed on the backup drive when their job or server was removed, grouped by server,
/// for finding and deleting them. Hidden while there are none.
struct RemovedJobsSection: View {
    let hive: KnownHive
    let link: HiveLink
    let statuses: JobStatusStore

    @State private var removedJobs: [RemovedJob] = []
    @State private var shown: RemovedJob?
    @State private var deletion: SnapshotDeletionRequest?

    var body: some View {
        Group {
            if !removedJobs.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(servers, id: \.id) { server in
                            serverRows(server)
                        }
                    }
                    .padding(4)
                } label: {
                    Text("Snapshots of Removed Jobs")
                }
            }
        }
        .task(id: statuses.logRevision) { await load() }
        .sheet(item: $shown) { job in
            RemovedJobSheet(hive: hive, link: link, job: job, statuses: statuses)
        }
        .snapshotDeletion($deletion, link: link) { Task { await load() } }
    }

    private struct ServerGroup {
        let id: UUID
        let name: String
        let isRemoved: Bool
        let jobs: [RemovedJob]
    }

    private var servers: [ServerGroup] {
        Dictionary(grouping: removedJobs, by: \.serverID)
            .map { id, jobs in ServerGroup(id: id, name: jobs[0].serverName, isRemoved: jobs[0].isServerRemoved, jobs: jobs) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @ViewBuilder private func serverRows(_ server: ServerGroup) -> some View {
        HStack {
            Label(server.isRemoved ? "\(server.name) (removed)" : server.name, systemImage: "server.rack")
                .font(.headline)
            Spacer()
            if server.isRemoved {
                Button("Delete All Snapshots…", systemImage: "trash", role: .destructive) {
                    deletion = SnapshotDeletionRequest(scope: .server(id: server.id), name: server.name)
                }
            }
        }
        ForEach(server.jobs) { job in
            Button { shown = job } label: {
                HStack {
                    Label(job.jobName, systemImage: "archivebox")
                    Spacer()
                    Text(Self.summary(of: job))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.forward")
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.leading, 20)
        }
    }

    private static func summary(of job: RemovedJob) -> String {
        let size = job.usedBytes.map { ", \($0.formatted(.byteCount(style: .file)))" } ?? ""
        return "\(SnapshotCount(job.snapshotCount))\(size), newest \(job.newestSnapshotAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private func load() async {
        guard let listed: [RemovedJob] = try? await link.perform({ try await $0.get(HiveEndpoint.removedJobs) }) else { return }
        removedJobs = listed
    }
}

/// A removed job's snapshots, to look through and delete.
private struct RemovedJobSheet: View {
    let hive: KnownHive
    let link: HiveLink
    let job: RemovedJob
    let statuses: JobStatusStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text(
                        job.isServerRemoved
                            ? "“\(job.jobName)” was removed with its server, “\(job.serverName)”. Its snapshots stayed on the backup drive."
                            : "“\(job.jobName)” was removed from “\(job.serverName)”. Its snapshots stayed on the backup drive."
                    )
                    .foregroundStyle(.secondary)
                }
                JobSnapshotsSection(hive: hive, link: link, jobID: job.jobID, jobName: job.jobName, statuses: statuses)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .macSheetSize(width: 560, height: 520)
    }
}
