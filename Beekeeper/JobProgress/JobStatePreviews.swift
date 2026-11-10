#if DEBUG
import HiveKit
import SwiftUI

/// Every state the job status, status badges and snapshot rows can show, with made-up runs.
private enum PreviewStates {
    static let serverID = UUID()
    static let started = Date.now.addingTimeInterval(-90)

    static let job = BackupJob(
        id: UUID(),
        serverID: serverID,
        name: "Example site",
        directories: [
            BackupDirectory(path: "/srv/sites/example/uploads", folder: "uploads"),
            BackupDirectory(path: "/srv/sites/example/images", folder: "images"),
            BackupDirectory(path: "/srv/sites/example/config", folder: "config"),
        ],
        databases: [
            BackupDatabase(
                id: UUID(),
                settings: DatabaseSettings(kind: .mysql, location: .container(serviceName: "example_db"), user: "site", name: "site"),
                hasPassword: true
            ),
        ],
        times: [TimeOfDay(hour: 3, minute: 0)],
        retention: .suggested
    )

    static func directory(_ folder: String, failure: BackupFailure? = nil) -> DirectoryRun {
        DirectoryRun(
            folder: folder,
            seconds: 12,
            filesTransferred: 3,
            bytesTransferred: 2_400_000,
            bytesReceived: 400_000,
            totalBytes: 180_000_000,
            vanishedFiles: false,
            failure: failure
        )
    }

    static func entry(
        finishedAfter seconds: TimeInterval? = 95,
        failure: BackupFailure? = nil,
        directories: [DirectoryRun] = [directory("uploads"), directory("images"), directory("config")],
        databases: [DatabaseRun] = [DatabaseRun(name: "site", seconds: 3, bytesDumped: 1_100_000, bytesStored: 40_000, failure: nil)]
    ) -> RunLogEntry {
        RunLogEntry(
            id: Int64.random(in: 1 ... 1_000_000),
            serverID: serverID,
            serverName: "Test Server",
            jobName: job.name,
            trigger: .scheduled,
            run: BackupRun(
                jobID: job.id,
                startedAt: started,
                finishedAt: seconds.map { started.addingTimeInterval($0) },
                failure: failure,
                directories: directories,
                databases: databases,
                pickedUpPartialSnapshot: false
            )
        )
    }

    struct State {
        let job: BackupJob
        let status: JobStatus

        /// Each state is a job of its own, named for the state, so one store can hold them all.
        init(_ title: String, _ state: JobRunState, lastRun: RunLogEntry?, overdueSince: Date? = nil, step: RunStep? = nil, done: Int = 0) {
            job = PreviewStates.job.renamed(title)
            let current = step.map { _ in
                let finished = PreviewStates.entry()
                return PreviewStates.entry(
                    finishedAfter: nil,
                    directories: Array(finished.run.directories.prefix(done)),
                    databases: Array(finished.run.databases.prefix(max(done - 3, 0)))
                )
            }
            status = JobStatus(
                jobID: job.id,
                state: state,
                current: current,
                step: step,
                lastRun: lastRun,
                lastSnapshotAt: lastRun?.run.finishedAt,
                nextRunAt: Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 3, minute: 0), matchingPolicy: .nextTime),
                overdueSince: overdueSince
            )
        }
    }

    static let states: [State] = [
        State("Never run", .idle, lastRun: nil),
        State("Succeeded", .idle, lastRun: entry()),
        State("Failed", .idle, lastRun: entry(failure: .databaseLoginRefused, databases: [
            DatabaseRun(name: "site", seconds: 1, bytesDumped: 0, bytesStored: 0, failure: .databaseLoginRefused),
        ])),
        State("Cancelled", .idle, lastRun: entry(failure: .cancelled, directories: [directory("uploads")], databases: [])),
        State("Interrupted by a restart", .idle, lastRun: entry(failure: .interrupted, directories: [directory("uploads")], databases: [])),
        State("Overdue", .idle, lastRun: entry(), overdueSince: .now.addingTimeInterval(-86400)),
        State(
            "Overdue after failing",
            .idle,
            lastRun: entry(failure: .unreachable, directories: [], databases: []),
            overdueSince: .now.addingTimeInterval(-2 * 86400)
        ),
        State("Waiting behind another run", .waiting, lastRun: entry()),
        State("Running: waiting for the drive", .running, lastRun: entry(), step: .waitingForDrive),
        State("Running: checking directories", .running, lastRun: entry(), step: .checkingDirectories),
        State("Running: copying", .running, lastRun: entry(), step: .pulling(folder: "images"), done: 1),
        State("Running: dumping", .running, lastRun: entry(), step: .dumping(database: "site"), done: 3),
        State("Running: finishing", .running, lastRun: entry(), step: .completing, done: 4),
    ]

    static var link: HiveLink {
        HiveLink(hive: KnownHive(id: UUID(), name: "Preview", addresses: [], isOnThisMac: true), keychain: DeviceKeychain())
    }

    static var store: JobStatusStore {
        JobStatusStore(link: link, previewing: states.map(\.status))
    }

    static let snapshots: [SnapshotSummary] = [
        snapshot(hoursAgo: 0, .partial, frees: nil),
        snapshot(hoursAgo: 1, .complete, frees: 45_000),
        snapshot(hoursAgo: 24, .complete, frees: nil),
        snapshot(hoursAgo: 40 * 24, .removing, frees: 82_000),
    ]

    static func snapshot(hoursAgo: Double, _ state: SnapshotSummary.State, frees: Int64?) -> SnapshotSummary {
        SnapshotSummary(id: UUID(), date: .now.addingTimeInterval(-hoursAgo * 3600), state: state, folder: "snapshot", freesBytes: frees)
    }
}

private extension BackupJob {
    func renamed(_ name: String) -> BackupJob {
        BackupJob(
            id: UUID(),
            serverID: serverID,
            name: name,
            directories: directories,
            databases: databases,
            times: times,
            retention: retention
        )
    }
}

#Preview("Job status") {
    let store = PreviewStates.store
    Form {
        ForEach(PreviewStates.states, id: \.job.id) { state in
            Section { EmptyView() } header: {
                Text(state.job.name)
                    .font(.title3.bold())
            }
            JobStatusSection(job: state.job, statuses: store)
        }
    }
    .formStyle(.grouped)
    .frame(width: 640, height: 900)
}

#Preview("Status badges") {
    List {
        Section("Jobs, as in the sidebar") {
            ForEach(PreviewStates.states, id: \.job.id) { state in
                HStack(spacing: 6) {
                    Label(state.job.name, systemImage: "archivebox")
                    Spacer()
                    JobHealthBadge(health: JobHealth(state.status))
                }
            }
        }
        Section("A server takes its most pressing job's") {
            HStack(spacing: 6) {
                Label("Test Server", systemImage: "server.rack")
                Spacer()
                JobHealthBadge(health: JobHealth(jobs: PreviewStates.states.map(\.job), in: PreviewStates.store))
            }
        }
    }
    .listStyle(.sidebar)
    .frame(width: 320, height: 600)
}

#Preview("Snapshot rows") {
    Form {
        Section("Snapshots") {
            ForEach(PreviewStates.snapshots) { snapshot in
                SnapshotRow(snapshot: snapshot, folder: snapshot.state == .removing ? nil : URL(filePath: "/Volumes/Hive Test Drive"))
            }
        }
    }
    .formStyle(.grouped)
    .frame(width: 560, height: 320)
}
#endif
