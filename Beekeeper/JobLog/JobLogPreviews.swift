#if DEBUG
import HiveKit
import SwiftUI

/// A job log with made-up runs and removals, each kind of entry it can show. Choose an iPad in the
/// canvas's device menu to see it as iPad shows it.
private enum PreviewLog {
    static let testServer = Server(
        id: UUID(),
        name: "Test Server",
        connection: ServerConnection(host: "127.0.0.1", port: 2222, user: "root"),
        quotaBytes: nil,
        confirmedHostKey: nil,
        sshKeyFingerprint: nil
    )
    static let webServer = Server(
        id: UUID(),
        name: "buzzingpixel-hetzner-docker",
        connection: ServerConnection(host: "buzzingpixel-hetzner-docker", user: "root"),
        quotaBytes: nil,
        confirmedHostKey: nil,
        sshKeyFingerprint: nil
    )

    static let exampleSite = job("Example Site - foo", on: testServer)
    static let buzzingpixel = job("buzzingpixel", on: webServer)

    static func job(_ name: String, on server: Server) -> BackupJob {
        BackupJob(
            id: UUID(),
            serverID: server.id,
            name: name,
            directories: [],
            databases: [],
            times: [TimeOfDay(hour: 0, minute: 0)],
            retention: .suggested
        )
    }

    static func hoursAgo(_ hours: Double) -> Date {
        .now.addingTimeInterval(-hours * 3600)
    }

    static func run(
        _ job: BackupJob,
        on server: Server,
        startedHoursAgo hours: Double,
        seconds: Double? = 4,
        trigger: RunTrigger = .scheduled,
        failure: BackupFailure? = nil,
        withContents: Bool = true
    ) -> JobLogEntry {
        let started = hoursAgo(hours)
        let directories = withContents ? ["uploads", "images/galleries", "config"].map { folder in
            DirectoryRun(
                folder: folder,
                seconds: 0.4,
                filesTransferred: folder == "uploads" ? 3 : 0,
                bytesTransferred: folder == "uploads" ? 161_000 : 0,
                bytesReceived: 0,
                totalBytes: 40_000_000,
                vanishedFiles: false,
                failure: nil
            )
        } : []
        let databases = withContents ? ["site", "shop", "blog", "notes"].map { name in
            DatabaseRun(name: name, seconds: 0.3, bytesDumped: 400_000, bytesStored: 40_000, failure: nil)
        } : []
        return .run(RunLogEntry(
            id: Int64.random(in: 1 ... 1_000_000),
            serverID: server.id,
            serverName: server.name,
            jobName: job.name,
            trigger: trigger,
            run: BackupRun(
                jobID: job.id,
                startedAt: started,
                finishedAt: seconds.map { started.addingTimeInterval($0) },
                failure: failure,
                directories: directories,
                databases: databases,
                pickedUpPartialSnapshot: false
            )
        ))
    }

    static func removal(_ job: BackupJob, on server: Server, hoursAgo hours: Double, couldNotRemove: Bool = false) -> JobLogEntry {
        let removed = RemovedSnapshot(
            snapshotID: UUID(),
            date: hoursAgo(hours + 30 * 24),
            wasComplete: true,
            reason: .outsideTiers,
            bytesFreed: 168_000
        )
        let notRemoved = UnremovedSnapshot(
            snapshotID: UUID(),
            date: hoursAgo(hours + 31 * 24),
            wasComplete: true,
            reason: .outsideTiers,
            problem: .couldNotRemove
        )
        return .removal(RemovalLogEntry(
            id: Int64.random(in: 1 ... 1_000_000),
            jobID: job.id,
            serverID: server.id,
            serverName: server.name,
            jobName: job.name,
            date: hoursAgo(hours),
            removed: [removed],
            notRemoved: couldNotRemove ? [notRemoved] : []
        ))
    }

    static let entries: [JobLogEntry] = [
        run(exampleSite, on: testServer, startedHoursAgo: 0.02, seconds: nil, trigger: .runNow),
        removal(exampleSite, on: testServer, hoursAgo: 0.5),
        run(exampleSite, on: testServer, startedHoursAgo: 0.5),
        run(exampleSite, on: testServer, startedHoursAgo: 2, trigger: .runNow),
        run(buzzingpixel, on: webServer, startedHoursAgo: 16, seconds: 0.4, failure: .driveMissing, withContents: false),
        removal(buzzingpixel, on: webServer, hoursAgo: 18, couldNotRemove: true),
        run(exampleSite, on: testServer, startedHoursAgo: 24, failure: .cancelled),
        run(buzzingpixel, on: webServer, startedHoursAgo: 40, seconds: 15),
        run(exampleSite, on: testServer, startedHoursAgo: 48, trigger: .afterInterruption),
    ]
}

private struct JobLogPreview: View {
    @State private var filter = JobLogFilter()

    var body: some View {
        NavigationStack {
            JobLogList(
                entries: PreviewLog.entries,
                filter: $filter,
                servers: [PreviewLog.testServer, PreviewLog.webServer],
                jobs: [PreviewLog.exampleSite, PreviewLog.buzzingpixel],
                onShowOlder: {
                    // Nothing older in a preview.
                }
            )
            .navigationTitle("Karrin")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

#Preview("Job log") {
    JobLogPreview()
}
#endif
