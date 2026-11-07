import Foundation
import HiveKit

/// Which of a job's snapshots its tiers keep (§10).
///
/// A day or a month counts only when the job has a complete snapshot in it, so a job that fails for
/// weeks keeps the history it had. Each kept day keeps its newest snapshot, so a job that runs several
/// times a day keeps only the last of each earlier day. Days and months are the Hive Mac's, so a
/// snapshot made just after midnight belongs to the day it's in there, whatever its UTC folder name
/// says, and a day the clocks change is still one day.
struct TierResolver {
    struct Decision: Equatable {
        let kept: Set<UUID>
        /// Kept by the daily tier alone, oldest first: what a quota may remove.
        let dailyOnly: [SnapshotRecord]
        /// Oldest first.
        let removals: [Removal]
    }

    struct Removal: Equatable {
        let snapshot: SnapshotRecord
        let reason: RemovalReason
    }

    let calendar: Calendar

    /// `snapshots` are one job's, on one drive. Snapshots being removed are left out.
    func decide(_ snapshots: [SnapshotRecord], tiers: RetentionTiers) -> Decision {
        let complete = snapshots
            .filter { $0.state == .complete }
            .sorted { ($0.date, $0.startedAt, $0.id.uuidString) > ($1.date, $1.startedAt, $1.id.uuidString) }
        guard let newest = complete.first else {
            return Decision(kept: Set(snapshots.filter { $0.state == .partial }.map(\.id)), dailyOnly: [], removals: [])
        }

        let daily = newestOfEach([.year, .month, .day], in: complete, keeping: tiers.dailySnapshots)
        let monthly = newestOfEach([.year, .month], in: complete, keeping: tiers.monthlySnapshots)
        let keptComplete = daily.union(monthly).union([newest.id])

        // A partial started before the newest snapshot completed is one that run didn't pick up, and
        // no run will: a run picks up only the newest that still fits the job's directories.
        let partials = snapshots.filter { $0.state == .partial }
        let replaced = partials.filter { $0.startedAt < newest.date }

        let removals = (complete.filter { !keptComplete.contains($0.id) }.map { Removal(snapshot: $0, reason: .outsideTiers) }
            + replaced.map { Removal(snapshot: $0, reason: .replacedPartial) })
            .sorted { $0.snapshot.date < $1.snapshot.date }
        let dailyOnly = complete
            .filter { daily.contains($0.id) && !monthly.contains($0.id) && $0.id != newest.id }
            .reversed()

        return Decision(
            kept: keptComplete.union(partials.filter { $0.startedAt >= newest.date }.map(\.id)),
            dailyOnly: Array(dailyOnly),
            removals: removals
        )
    }

    /// The newest snapshot in each of the newest `count` periods that have one. `newestFirst` is sorted.
    private func newestOfEach(_ period: Set<Calendar.Component>, in newestFirst: [SnapshotRecord], keeping count: Int) -> Set<UUID> {
        var seen: Set<DateComponents> = []
        var kept: Set<UUID> = []
        for snapshot in newestFirst {
            guard seen.count < count || seen.contains(calendar.dateComponents(period, from: snapshot.date)) else { break }
            if seen.insert(calendar.dateComponents(period, from: snapshot.date)).inserted { kept.insert(snapshot.id) }
        }
        return kept
    }
}
