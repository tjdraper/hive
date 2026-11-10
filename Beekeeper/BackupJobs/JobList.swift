import Foundation
import HiveKit
import Observation

/// One Hive's backup jobs, as it last listed them, kept in step with what this device changes.
@Observable
final class JobList {
    private(set) var jobs: [BackupJob] = []
    private let link: HiveLink

    init(link: HiveLink) {
        self.link = link
    }

    func job(_ id: UUID) -> BackupJob? {
        jobs.first { $0.id == id }
    }

    func jobs(onServer serverID: UUID) -> [BackupJob] {
        jobs.filter { $0.serverID == serverID }
    }

    /// Keeps the last list when the Hive can't be reached, so the sidebar doesn't empty while it's offline.
    func refresh() async {
        guard let listed: [BackupJob] = try? await link.perform({ try await $0.get(HiveEndpoint.jobs) }) else { return }
        jobs = Self.sorted(listed)
    }

    func add(_ draft: BackupJobDraft, toServer serverID: UUID) async throws -> BackupJob {
        let job: BackupJob = try await link.perform { try await $0.post(HiveEndpoint.jobs(onServer: serverID), body: draft) }
        update(job)
        return job
    }

    /// With a `reason`, asks for Touch ID or the password first, saying that.
    func change(_ id: UUID, to draft: BackupJobDraft, confirming reason: String?) async throws -> BackupJob {
        let job: BackupJob = try await link.confirmed("PUT", HiveEndpoint.job(id), body: draft, reason: reason)
        update(job)
        return job
    }

    func remove(_ id: UUID) async throws {
        try await link.perform { try await $0.delete(HiveEndpoint.job(id)) }
        jobs.removeAll { $0.id == id }
    }

    /// How many snapshots `tiers` would remove that the job's saved tiers don't.
    func estimate(tiers: RetentionTiers, of id: UUID) async throws -> RemovalEstimate {
        try await link.perform { try await $0.post(HiveEndpoint.retentionEstimate(ofJob: id), body: tiers) }
    }

    /// Hive removes a server's jobs with it.
    func forgetJobs(onServer serverID: UUID) {
        jobs.removeAll { $0.serverID == serverID }
    }

    private func update(_ job: BackupJob) {
        jobs.removeAll { $0.id == job.id }
        jobs = Self.sorted(jobs + [job])
    }

    private static func sorted(_ jobs: [BackupJob]) -> [BackupJob] {
        jobs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
