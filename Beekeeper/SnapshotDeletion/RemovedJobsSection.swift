import HiveKit
import SwiftUI

/// Snapshots that stayed on the backup drive when their job or server was removed, grouped by server,
/// for finding and deleting them. Hidden while there are none.
struct RemovedJobsSection: View {
    let hive: KnownHive
    let link: HiveLink
    let statuses: JobStatusStore
    let removed: RemovedJobList

    @Environment(\.presentFormSheet) private var presentSheet
    @State private var deletion: SnapshotDeletionRequest?

    var body: some View {
        if !removed.jobs.isEmpty {
            Section("Snapshots of Removed Jobs") {
                ForEach(servers, id: \.id) { server in
                    serverRows(server)
                }
            }
            .snapshotDeletion($deletion, link: link) { Task { await removed.load(link) } }
        }
    }

    private struct ServerGroup {
        let id: UUID
        let name: String
        let isRemoved: Bool
        let jobs: [RemovedJob]
    }

    private var servers: [ServerGroup] {
        Dictionary(grouping: removed.jobs, by: \.serverID)
            .map { id, jobs in ServerGroup(id: id, name: jobs[0].serverName, isRemoved: jobs[0].isServerRemoved, jobs: jobs) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @ViewBuilder
    private func serverRows(_ server: ServerGroup) -> some View {
        Label(server.isRemoved ? "\(server.name) (removed)" : server.name, systemImage: "server.rack")
            .font(.headline)
        ForEach(server.jobs) { job in
            Button { show(job) } label: {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.jobName)
                            Text(Self.summary(of: job))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "archivebox")
                    }
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.leading, 20)
        }
        if server.isRemoved {
            Button("Delete All Snapshots…", systemImage: "trash", role: .destructive) {
                deletion = SnapshotDeletionRequest(scope: .server(id: server.id), name: server.name)
            }
            .padding(.leading, 20)
        }
    }

    private func show(_ job: RemovedJob) {
        presentSheet? {
            RemovedJobSheet(hive: hive, link: link, job: job, statuses: statuses)
        }
    }

    private static func summary(of job: RemovedJob) -> String {
        let size = job.usedBytes.map { ", \($0.formatted(.byteCount(style: .file)))" } ?? ""
        return "\(SnapshotCount(job.snapshotCount))\(size), newest \(job.newestSnapshotAt.formatted(date: .abbreviated, time: .omitted))"
    }

}

/// The jobs whose snapshots outlived them. The overview keeps it, since a form runs nothing for a
/// section that isn't showing.
@Observable
final class RemovedJobList {
    private(set) var jobs: [RemovedJob] = []

    func load(_ link: HiveLink) async {
        guard let listed: [RemovedJob] = try? await link.perform({ try await $0.get(HiveEndpoint.removedJobs) }) else { return }
        jobs = listed
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
        SheetLayout(title: "Snapshots of “\(job.jobName)”", confirm: SheetButton(title: "Done") { dismiss() }) {
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
        }
        .macSheetSize(width: 560, height: 520)
    }
}
