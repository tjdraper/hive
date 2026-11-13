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
        JobLogList(
            entries: entries.map(live),
            filter: $filter,
            servers: servers.servers,
            jobs: servers.jobs.jobs,
            onShowOlder: nextBefore.map { before in { Task { await loadOlder(before: before) } } }
        )
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
    private func live(_ entry: JobLogEntry) -> JobLogEntry {
        guard case .run(let run) = entry, run.run.finishedAt == nil,
              let current = servers.statuses.status(of: run.run.jobID)?.current, current.id == run.id
        else { return entry }
        return .run(current)
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

/// The entries with the filters above them, apart from loading them, so a preview can show made-up ones.
struct JobLogList: View {
    let entries: [JobLogEntry]
    @Binding var filter: JobLogFilter
    let servers: [Server]
    let jobs: [BackupJob]
    /// Nil once the oldest page is showing.
    let onShowOlder: (() -> Void)?

    var body: some View {
        List {
            ForEach(entries) { entry in
                switch entry {
                case .run(let run):
                    RunLogRow(entry: run, showsJob: filter.jobID == nil)
                case .removal(let removal):
                    RemovalLogRow(entry: removal, showsJob: filter.jobID == nil)
                }
            }
            if let onShowOlder {
                Button("Show Older", action: onShowOlder)
            }
        }
        #if os(iOS)
        // Full-width rows, as on the Mac, rather than iOS's inset card.
        .listStyle(.plain)
        #endif
        .safeAreaInset(edge: .top, spacing: 0) {
            JobLogFilterBar(filter: $filter, servers: servers, allJobs: jobs)
        }
    }
}

private struct JobLogFilterBar: View {
    @Binding var filter: JobLogFilter
    let servers: [Server]
    let allJobs: [BackupJob]

    var body: some View {
        HStack(spacing: 12) {
            Picker("Server", selection: $filter.serverID) {
                Text("All Servers").tag(UUID?.none)
                Divider()
                ForEach(servers) { server in
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
                #if os(iOS)
                // A switch would stretch across the bar, away from its label.
                .toggleStyle(.button)
                #endif
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
        filter.serverID.map { serverID in allJobs.filter { $0.serverID == serverID } } ?? allJobs
    }
}
