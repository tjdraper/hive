import HiveKit
import SwiftUI

/// One backup job: where it stands, what it backs up, when, what it keeps and its snapshots, with
/// running, editing and removing it.
struct JobDetail: View {
    let hive: KnownHive
    let link: HiveLink
    let servers: ServerList
    let jobID: UUID
    let onShowHive: () -> Void
    let onShowServer: () -> Void

    @State private var editRequest: JobEditRequest?

    private var job: BackupJob? {
        servers.jobs.job(jobID)
    }

    var body: some View {
        HiveConnectionGate(hive: hive, link: link) {
            if let job {
                page(job)
            } else {
                ContentUnavailableView("Job Not Found", systemImage: "archivebox", description: Text("It may have been removed."))
            }
        }
        .navigationTitle(job?.name ?? "Job")
        .locationPath([
            LocationPath.Part(title: hive.name, systemImage: "hexagon", action: onShowHive),
            LocationPath.Part(
                title: job.flatMap { servers.server($0.serverID) }?.name ?? "Server",
                systemImage: "server.rack",
                action: onShowServer
            ),
            LocationPath.Part(title: job?.name ?? "Job", systemImage: "archivebox"),
        ])
    }

    private func page(_ job: BackupJob) -> some View {
        Form {
            JobStatusSection(job: job, statuses: servers.statuses)
            JobSummary(job: job)
            JobSnapshotsSection(hive: hive, link: link, job: job, statuses: servers.statuses)
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarSpacer(.flexible)
            ToolbarItemGroup {
                Button("Edit…") { editRequest = JobEditRequest(action: .edit, job: job, jobs: servers.jobs) }
                Button("Remove…", systemImage: "trash", role: .destructive) {
                    editRequest = JobEditRequest(action: .remove, job: job, jobs: servers.jobs)
                }
                .help("Remove this job")
            }
        }
        .jobEditing($editRequest) { _ in onShowServer() }
    }
}

/// The job's configuration as Hive has it, read-only.
private struct JobSummary: View {
    let job: BackupJob

    var body: some View {
        Section("Directories") {
            if job.directories.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            }
            ForEach(job.directories, id: \.self) { directory in
                LabeledContent {
                    Text(directory.folder)
                } label: {
                    Text(directory.path)
                        .textSelection(.enabled)
                }
            }
        }
        Section("Databases") {
            if job.databases.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            }
            ForEach(job.databases) { database in
                LabeledContent {
                    if !database.hasPassword {
                        Text("No password")
                            .foregroundStyle(.orange)
                    }
                } label: {
                    Text(database.settings.name)
                    Text(database.settings.summary)
                }
            }
        }
        Section("Runs At") {
            Text(job.times.map(\.formatted).formatted(.list(type: .and)))
        }
        Section("Keeps") {
            LabeledContent("Daily snapshots", value: String(job.retention.dailySnapshots))
            LabeledContent("Monthly snapshots", value: String(job.retention.monthlySnapshots))
        }
    }
}

extension DatabaseSettings {
    /// Its kind, where it runs and who Hive signs in as, in a line.
    var summary: String {
        let kind = switch kind {
        case .mysql: "MySQL or MariaDB"
        case .postgres: "Postgres"
        }
        let place = switch location {
        case .host: "on the server"
        case .container(let serviceName): "in “\(serviceName)”"
        }
        return "\(kind) \(place), as \(user)"
    }
}

extension TimeOfDay {
    /// In the Hive Mac's time zone, as Hive runs it, written the way this device writes times.
    var formatted: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let date = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)) ?? .distantPast
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = .gmt
        return date.formatted(style)
    }
}
