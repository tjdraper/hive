import Foundation
import GRDB
import HiveKit
import ScoutProtocol

/// A server's container groups and services over a range, for Beekeeper's charts. Buckets are sized as
/// `MetricsSeriesReader` sizes them, read from the 10-second samples while the range's start is
/// within the day they're kept for, and otherwise from the hours, in buckets of at least an hour.
struct CgroupSeriesReader: Sendable {
    let database: MetricsDatabase
    let now: @Sendable () -> Date

    /// `range` is seconds since 1970 on the server's clock.
    func series(ofServer serverID: UUID, over range: Range<Int64>) throws -> CgroupSeries {
        let hiveNow = Int64(now().timeIntervalSince1970.rounded(.down))
        return try database.writer.read { database in
            let server = try Row.fetchOne(
                database,
                sql: "SELECT id, clockOffsetSeconds FROM metricsServer WHERE serverID = ?",
                arguments: [serverID]
            )
            let serverNow = hiveNow + (server?["clockOffsetSeconds"] ?? 0)
            var bucketSeconds = MetricsSeriesReader.bucketSeconds(for: range, serverNow: serverNow)
            let pruningSlack = Int64(MetricsUpkeep.interval.components.seconds)
            let fromSamples = range.lowerBound >= serverNow - MetricsUpkeep.cgroupSampleKeptSeconds - pruningSlack
            if !fromSamples { bucketSeconds = max(bucketSeconds, MetricsResolution.hour.seconds) }
            guard let serverKey: Int64 = server?["id"] else {
                return CgroupSeries(bucketSeconds: bucketSeconds, containers: [], services: [])
            }

            var buckets: [Int64: (containers: [HourlyCgroupGroup], services: [HourlyCgroupGroup])] = [:]
            if fromSamples {
                let names = try ContainerName.kept(forServer: serverKey, in: database)
                var samples: [Int64: [(containers: [CgroupGroupFigures], services: [CgroupGroupFigures])]] = [:]
                for row in try Row.fetchAll(database, sql: """
                SELECT startsAt, containers, services FROM cgroupTenSeconds WHERE serverKey = ? AND startsAt >= ? AND startsAt < ?
                """, arguments: [serverKey, range.lowerBound, range.upperBound]) {
                    let sample = try StoredCgroupSample(row: row)
                    samples[Self.floor(sample.startsAt, to: bucketSeconds), default: []].append(sample.grouped(names: names))
                }
                for (start, grouped) in samples {
                    buckets[start] = (CgroupGrouping.combined(grouped.map(\.containers)), CgroupGrouping.combined(grouped.map(\.services)))
                }
            } else {
                var hours: [Int64: [StoredCgroupHour]] = [:]
                for row in try Row.fetchAll(database, sql: """
                SELECT startsAt, sampleCount, containers, services FROM cgroupHour WHERE serverKey = ? AND startsAt >= ? AND startsAt < ?
                """, arguments: [serverKey, Self.floor(range.lowerBound, to: bucketSeconds), range.upperBound]) {
                    let hour = try StoredCgroupHour(row: row)
                    hours[Self.floor(hour.startsAt, to: bucketSeconds), default: []].append(hour)
                }
                for (start, stored) in hours {
                    buckets[start] = (
                        CgroupGrouping.combined(hours: stored.map { ($0.sampleCount, $0.containers) }),
                        CgroupGrouping.combined(hours: stored.map { ($0.sampleCount, $0.services) })
                    )
                }
            }

            let starts = buckets.keys.sorted()
            return CgroupSeries(
                bucketSeconds: bucketSeconds,
                containers: Self.series(starts.map { ($0, buckets[$0]?.containers ?? []) }),
                services: Self.series(starts.map { ($0, buckets[$0]?.services ?? []) })
            )
        }
    }

    /// A series for each group in any bucket, with every bucket, so one a group is missing from reads
    /// as nothing rather than a gap.
    private static func series(_ buckets: [(start: Int64, groups: [HourlyCgroupGroup])]) -> [CgroupGroupSeries] {
        var keys: [CgroupGroupKey] = []
        var seen: Set<CgroupGroupKey> = []
        for bucket in buckets {
            for group in bucket.groups where seen.insert(group.key).inserted {
                keys.append(group.key)
            }
        }
        return keys.map { key in
            let groups = buckets.map { bucket in bucket.groups.first { $0.key == key } }
            return CgroupGroupSeries(
                name: key.name,
                kind: key.kind,
                composeProject: key.composeProject,
                bucketStarts: buckets.map(\.start),
                averageCPUCores: groups.map { $0?.averageCPUCores ?? 0 },
                highestCPUCores: groups.map { $0?.highestCPUCores ?? 0 },
                averageMemoryBytes: groups.map { $0?.averageMemoryBytes ?? 0 },
                highestMemoryBytes: groups.map { $0?.highestMemoryBytes ?? 0 }
            )
        }
        .sorted { ($0.composeProject ?? "", $0.name) < ($1.composeProject ?? "", $1.name) }
    }

    private static func floor(_ time: Int64, to seconds: Int64) -> Int64 {
        time - ((time % seconds) + seconds) % seconds
    }
}
