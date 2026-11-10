import HiveKit
import SwiftUI

/// What each run did and what retention removed, newest first, for one server or job or all of them.
struct JobLogView: View {
    let link: HiveLink
    let servers: ServerList

    @State private var filter = JobLogFilter()
    @State private var entries: [JobLogEntry] = []
    @State private var nextBefore: Int64?
    @State private var failure: String?
    @State private var hasLoaded = false

    var body: some View {
        List {
            ForEach(entries) { entry in
                switch entry {
                case .run(let run):
                    RunLogRow(entry: live(run), showsJob: filter.jobID == nil)
                case .removal(let removal):
                    RemovalLogRow(entry: removal, showsJob: filter.jobID == nil)
                }
            }
            if let nextBefore {
                Button("Show Older") {
                    Task { await loadOlder(before: nextBefore) }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            JobLogFilterBar(filter: $filter, servers: servers)
        }
        .overlay {
            if let failure {
                ContentUnavailableView("Couldn't Load the Job Log", systemImage: "exclamationmark.triangle", description: Text(failure))
            } else if hasLoaded, entries.isEmpty {
                ContentUnavailableView(
                    filter.problemsOnly ? "No Problems" : "No Runs Yet",
                    systemImage: filter.problemsOnly ? "checkmark.circle" : "list.bullet.rectangle"
                )
            }
        }
        .task(id: filter) {
            entries = []
            nextBefore = nil
            hasLoaded = false
            await loadNewest()
        }
        .onChange(of: servers.statuses.logRevision) {
            Task { await loadNewest() }
        }
        .refreshable { await loadNewest() }
    }

    /// A run still going, as far as live updates have it.
    private func live(_ entry: RunLogEntry) -> RunLogEntry {
        guard entry.run.finishedAt == nil, let current = servers.statuses.status(of: entry.run.jobID)?.current,
              current.id == entry.id
        else { return entry }
        return current
    }

    /// Keeps older pages already shown when the newest page reaches back to them.
    private func loadNewest() async {
        guard let page = await load(before: nil) else { return }
        if let oldestNew = page.entries.last?.id, let newestShown = entries.first?.id, oldestNew <= newestShown {
            entries = page.entries + entries.filter { $0.id < oldestNew }
        } else {
            entries = page.entries
            nextBefore = page.nextBefore
        }
    }

    private func loadOlder(before: Int64) async {
        guard let page = await load(before: before) else { return }
        entries += page.entries
        nextBefore = page.nextBefore
    }

    private func load(before: Int64?) async -> JobLogPage? {
        let path = filter.path(before: before)
        defer { hasLoaded = true }
        do {
            let page: JobLogPage = try await link.perform { try await $0.get(path) }
            failure = nil
            return page
        } catch where !Task.isCancelled {
            failure = HiveLink.message(for: error)
            return nil
        } catch {
            // A newer load replaced it.
            return nil
        }
    }
}

private struct JobLogFilterBar: View {
    @Binding var filter: JobLogFilter
    let servers: ServerList

    var body: some View {
        HStack(spacing: 12) {
            Picker("Server", selection: $filter.serverID) {
                Text("All Servers").tag(UUID?.none)
                Divider()
                ForEach(servers.servers) { server in
                    Text(server.name).tag(Optional(server.id))
                }
            }
            .fixedSize()
            Picker("Job", selection: $filter.jobID) {
                Text("All Jobs").tag(UUID?.none)
                Divider()
                ForEach(jobs) { job in
                    Text(job.name).tag(Optional(job.id))
                }
            }
            .fixedSize()
            .disabled(jobs.isEmpty)
            Toggle("Problems Only", isOn: $filter.problemsOnly)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .onChange(of: filter.serverID) {
            if let jobID = filter.jobID, !jobs.contains(where: { $0.id == jobID }) { filter.jobID = nil }
        }
    }

    private var jobs: [BackupJob] {
        filter.serverID.map { servers.jobs.jobs(onServer: $0) } ?? servers.jobs.jobs
    }
}
