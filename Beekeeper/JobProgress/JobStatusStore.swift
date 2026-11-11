import Foundation
import HiveKit
import Observation

/// Where each of one Hive's jobs stands, kept up to date from the Hive's live updates.
@Observable
final class JobStatusStore {
    private(set) var statuses: [UUID: JobStatus] = [:]
    /// Whether live updates are arriving. While they aren't, the statuses are as last heard.
    private(set) var isLive = false
    /// Goes up with each new job log entry, which changes a job's snapshots, and on each reconnect,
    /// since entries may have been missed meanwhile.
    private(set) var logRevision = 0
    private let link: HiveLink

    init(link: HiveLink) {
        self.link = link
    }

    #if DEBUG
    /// For previews: shows `statuses` as if the Hive had sent them.
    init(link: HiveLink, previewing statuses: [JobStatus]) {
        self.link = link
        self.statuses = Dictionary(statuses.map { ($0.jobID, $0) }) { _, last in last }
    }
    #endif

    func status(of jobID: UUID) -> JobStatus? {
        statuses[jobID]
    }

    /// Fetches every job's status, which nothing live reports changing: a job going overdue as time
    /// passes, or a run's next time after its times change.
    func refresh() async {
        guard let listed: [JobStatus] = try? await link.perform({ try await $0.get(HiveEndpoint.jobStatus) }) else { return }
        statuses = Dictionary(listed.map { ($0.jobID, $0) }) { _, last in last }
    }

    func refresh(_ jobID: UUID) async {
        guard let status: JobStatus = try? await link.perform({ try await $0.get(HiveEndpoint.run(ofJob: jobID)) }) else { return }
        statuses[jobID] = status
    }

    /// False when the job was already waiting or running.
    func runNow(_ jobID: UUID) async throws -> Bool {
        do {
            let status: JobStatus = try await link.perform { try await $0.post(HiveEndpoint.run(ofJob: jobID)) }
            statuses[jobID] = status
            return true
        } catch let refused as HiveRequestError where refused.status == 409 {
            await refresh(jobID)
            return false
        }
    }

    func cancel(_ jobID: UUID) async throws {
        do {
            try await link.perform { try await $0.delete(HiveEndpoint.run(ofJob: jobID)) }
        } catch let refused as HiveRequestError where refused.status == 404 {
            // It finished first.
        }
        await refresh(jobID)
    }

    /// While live updates aren't arriving, the statuses stay as last heard.
    func liveUpdatesStopped() {
        isLive = false
    }

    func apply(_ update: LiveUpdate) {
        switch update {
        case .jobStatuses(let all):
            statuses = Dictionary(all.map { ($0.jobID, $0) }) { _, last in last }
            isLive = true
            logRevision += 1
        case .jobStatus(let status):
            statuses[status.jobID] = status
        case .event(.step(let jobID, let step)):
            statuses[jobID] = statuses[jobID]?.running(step: step)
        case .event(.progress(let entry)):
            let jobID = entry.run.jobID
            statuses[jobID] = statuses[jobID]?.running(current: entry)
        case .event(.finished), .event(.removed):
            logRevision += 1
        case .event(.queued), .event(.leftQueue), .event(.started):
            // A queued, cancelled or started run is followed by the job's new status.
            break
        case .heartbeat, .recovery, .addresses:
            break
        }
    }
}

private extension JobStatus {
    func running(step: RunStep? = nil, current: RunLogEntry? = nil) -> JobStatus {
        JobStatus(
            jobID: jobID,
            state: .running,
            current: current ?? self.current,
            step: step ?? self.step,
            lastRun: lastRun,
            lastSnapshotAt: lastSnapshotAt,
            nextRunAt: nextRunAt,
            overdueSince: overdueSince
        )
    }
}
