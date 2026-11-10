import HiveKit
import SwiftUI

/// A run: whether it worked, what it copied, and each directory and database on request.
struct RunLogRow: View {
    let entry: RunLogEntry
    let showsJob: Bool

    var body: some View {
        DisclosureGroup {
            ForEach(entry.run.directories, id: \.folder) { directory in
                DirectoryRunRow(directory: directory)
            }
            ForEach(entry.run.databases, id: \.name) { database in
                DatabaseRunRow(database: database)
            }
            if entry.run.pickedUpPartialSnapshot {
                Text("Carried on with the snapshot an earlier run left incomplete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    LogEntryTitle(jobName: entry.jobName, serverName: entry.serverName, showsJob: showsJob)
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let failure = entry.run.failure, failure != .cancelled {
                        Text(failure.message)
                            .font(.callout)
                            .foregroundStyle(failure == .interrupted ? .orange : .red)
                    }
                }
                Spacer()
                Text(entry.run.startedAt, format: .dateTime.month().day().hour().minute())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var icon: some View {
        if entry.run.finishedAt == nil {
            ProgressView()
                .controlSize(.mini)
        } else {
            RunResultIcon(failure: entry.run.failure)
        }
    }

    private var summary: String {
        var parts: [String] = []
        let run = entry.run
        if let duration = run.duration {
            parts.append(run.failure == .cancelled ? "Cancelled after \(duration.spoken)" : "Took \(duration.spoken)")
        } else {
            parts.append("Running")
        }
        if run.bytesWritten > 0 { parts.append("\(run.bytesWritten.formatted(.byteCount(style: .file))) written") }
        if run.vanishedFiles { parts.append("some files vanished while copying") }
        parts.append(entry.trigger.summary)
        return parts.joined(separator: " · ")
    }
}

/// What retention removed from one job, and anything it couldn't.
struct RemovalLogRow: View {
    let entry: RemovalLogEntry
    let showsJob: Bool

    var body: some View {
        DisclosureGroup {
            ForEach(entry.removed, id: \.snapshotID) { snapshot in
                LabeledContent {
                    Text(snapshot.bytesFreed.formatted(.byteCount(style: .file)))
                        .monospacedDigit()
                } label: {
                    Text(snapshot.date, format: .dateTime.year().month().day().hour().minute())
                    Text(snapshot.reason.summary)
                }
            }
            ForEach(entry.notRemoved, id: \.snapshotID) { snapshot in
                LabeledContent {
                    Text(snapshot.problem.summary)
                        .foregroundStyle(.red)
                } label: {
                    Text(snapshot.date, format: .dateTime.year().month().day().hour().minute())
                    Text(snapshot.reason.summary)
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: entry.notRemoved.isEmpty ? "trash.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(entry.notRemoved.isEmpty ? Color.secondary : Color.red)
                VStack(alignment: .leading, spacing: 2) {
                    LogEntryTitle(jobName: entry.jobName, serverName: entry.serverName, showsJob: showsJob)
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !entry.notRemoved.isEmpty {
                        Text("Couldn't remove \(Self.snapshots(entry.notRemoved.count)).")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                Text(entry.date, format: .dateTime.month().day().hour().minute())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    private var summary: String {
        let freed = entry.removed.reduce(0) { $0 + $1.bytesFreed }
        guard !entry.removed.isEmpty else { return "Retention" }
        return "Removed \(Self.snapshots(entry.removed.count)), freeing \(freed.formatted(.byteCount(style: .file)))"
    }

    private static func snapshots(_ count: Int) -> String {
        "\(count.formatted()) \(count == 1 ? "snapshot" : "snapshots")"
    }
}

private struct LogEntryTitle: View {
    let jobName: String
    let serverName: String
    let showsJob: Bool

    var body: some View {
        if showsJob {
            Text("\(Text(jobName).fontWeight(.medium)) on \(serverName)")
        } else {
            Text(jobName)
                .fontWeight(.medium)
        }
    }
}

private struct DirectoryRunRow: View {
    let directory: DirectoryRun

    var body: some View {
        LabeledContent {
            if let failure = directory.failure {
                Text(failure.message)
                    .foregroundStyle(.red)
            } else {
                Text(detail)
                    .monospacedDigit()
            }
        } label: {
            Label(directory.folder, systemImage: "folder")
            if directory.vanishedFiles {
                Text("Some files vanished on the server while they were copied.")
            }
        }
    }

    private var detail: String {
        let files = directory.filesTransferred
        guard files > 0 else { return "No changes · \(directory.seconds.spoken)" }
        let bytes = directory.bytesTransferred.formatted(.byteCount(style: .file))
        return "\(files.formatted()) new or changed \(files == 1 ? "file" : "files"), \(bytes) · \(directory.seconds.spoken)"
    }
}

private struct DatabaseRunRow: View {
    let database: DatabaseRun

    var body: some View {
        LabeledContent {
            if let failure = database.failure {
                Text(failure.message)
                    .foregroundStyle(.red)
            } else {
                Text("\(database.bytesStored.formatted(.byteCount(style: .file))) stored · \(database.seconds.spoken)")
                    .monospacedDigit()
            }
        } label: {
            Label(database.name, systemImage: "cylinder")
        }
    }
}

extension RunTrigger {
    var summary: String {
        switch self {
        case .scheduled: "Scheduled"
        case .runNow: "Run Now"
        case .afterInterruption: "Again after Hive restarted"
        }
    }
}

extension RemovalReason {
    var summary: String {
        switch self {
        case .outsideTiers: "No longer kept by the job's tiers"
        case .replacedPartial: "Incomplete, and a newer snapshot completed"
        case .quota: "The server was over its quota"
        }
    }
}

extension RemovalProblem {
    var summary: String {
        switch self {
        case .notInJobFolder: "It isn't in its job's folder, so Hive left it"
        case .beingWritten: "A run was writing to it"
        case .couldNotRemove: "Hive couldn't remove all of it, and tries again later"
        }
    }
}
