import Foundation
import GRDB
import os
import ScoutProtocol

/// The hourly pass over the metrics database (§6): each closed hour's top process groups, containers
/// and services, pruning to
/// each resolution's period, and removing what's left of servers no longer in Hive.
struct MetricsUpkeep: Sendable {
    static let interval: Duration = .seconds(3_600)
    static let processSampleKeptSeconds: Int64 = 86_400
    static let processHourKeptSeconds: Int64 = 14 * 86_400
    static let cgroupSampleKeptSeconds: Int64 = 86_400
    static let cgroupHourKeptSeconds: Int64 = 90 * 86_400
    /// A container's name is kept this long after a closed hour last held it. Its hours keep their names
    /// themselves, so this covers only its 10-second samples.
    static let containerNameSeconds: TimeInterval = 2 * 86_400
    /// A name stays this long after it's first seen, so dropping it can't reset the day's limit on new ones.
    static let newNameSeconds: TimeInterval = 86_400

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Metrics")

    let database: MetricsDatabase
    /// Every server in Hive's store, read after the metrics database's, so a server added in between
    /// is never taken for a removed one.
    let knownServerIDs: @Sendable () throws -> Set<UUID>
    let now: @Sendable () -> Date

    func run() async {
        while !Task.isCancelled {
            runOnce()
            try? await Task.sleep(for: Self.interval)
        }
    }

    func runOnce() {
        let start = ContinuousClock.now
        do {
            let removed = try removeServersNoLongerInHive()
            let now = now()
            let nowSeconds = Int64(now.timeIntervalSince1970.rounded(.down))
            let (hours, pruned) = try database.writer.write { database in
                let hours = try rollUpProcessHours(at: nowSeconds, in: database) + rollUpCgroupHours(at: now, in: database)
                return (hours, try prune(at: now, in: database))
            }
            let duration = ContinuousClock.now - start
            Self.logger.notice("""
            Metrics upkeep: \(hours, privacy: .public) process hours, \(pruned, privacy: .public) rows pruned, \
            \(removed, privacy: .public) removed servers, in \(duration, privacy: .public)
            """)
        } catch {
            Self.logger.error("Metrics upkeep failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func removeServersNoLongerInHive() throws -> Int {
        let kept = try database.writer.read { try UUID.fetchAll($0, sql: "SELECT serverID FROM metricsServer") }
        let known = try knownServerIDs()
        let gone = kept.filter { !known.contains($0) }
        guard !gone.isEmpty else { return 0 }
        return try database.writer.write { database in
            try MetricsServerRecord.filter(gone.contains(Column("serverID"))).deleteAll(database)
        }
    }

    /// An hour is closed once the server's newest sample, or its clock by Hive's, is past it. One whose
    /// samples grew since it was made, such as from a late batch, is made again.
    private func rollUpProcessHours(at nowSeconds: Int64, in database: Database) throws -> Int {
        let due = try Row.fetchAll(database, sql: """
        SELECT samples.serverKey, samples.hour
        FROM (
            SELECT serverKey, startsAt / 3600 * 3600 AS hour, COUNT(*) AS sampleCount
            FROM processTenSeconds GROUP BY serverKey, hour
        ) AS samples
        JOIN metricsServer ON metricsServer.id = samples.serverKey
        LEFT JOIN processHour ON processHour.serverKey = samples.serverKey AND processHour.startsAt = samples.hour
        WHERE samples.hour + 3600 <= MAX(IFNULL(metricsServer.lastSampleAt, 0), ? + IFNULL(metricsServer.clockOffsetSeconds, 0))
            AND samples.sampleCount > IFNULL(processHour.sampleCount, 0)
        """, arguments: [nowSeconds])
        for row in due {
            let serverKey: Int64 = row["serverKey"]
            let hour: Int64 = row["hour"]
            let blobs = try Data.fetchAll(
                database,
                sql: "SELECT groups FROM processTenSeconds WHERE serverKey = ? AND startsAt >= ? AND startsAt < ?",
                arguments: [serverKey, hour, hour + 3_600]
            )
            let samples = try blobs.map { try ProcessGroupStorage.decode([ProcessGroup].self, from: $0) }
            try database.execute(sql: """
            INSERT INTO processHour (serverKey, startsAt, sampleCount, groups) VALUES (?, ?, ?, ?)
            ON CONFLICT(serverKey, startsAt) DO UPDATE SET sampleCount = excluded.sampleCount, groups = excluded.groups
            """, arguments: [serverKey, hour, samples.count, ProcessGroupStorage.encode(ProcessGroupStorage.hourly(of: samples))])
        }
        return due.count
    }

    /// As for processes, with containers grouped by the names Hive knows when the hour closes. Every
    /// container the hour held keeps its name a while longer.
    private func rollUpCgroupHours(at now: Date, in database: Database) throws -> Int {
        let nowSeconds = Int64(now.timeIntervalSince1970.rounded(.down))
        let due = try Row.fetchAll(database, sql: """
        SELECT samples.serverKey, samples.hour
        FROM (
            SELECT serverKey, startsAt / 3600 * 3600 AS hour, COUNT(*) AS sampleCount
            FROM cgroupTenSeconds GROUP BY serverKey, hour
        ) AS samples
        JOIN metricsServer ON metricsServer.id = samples.serverKey
        LEFT JOIN cgroupHour ON cgroupHour.serverKey = samples.serverKey AND cgroupHour.startsAt = samples.hour
        WHERE samples.hour + 3600 <= MAX(IFNULL(metricsServer.lastSampleAt, 0), ? + IFNULL(metricsServer.clockOffsetSeconds, 0))
            AND samples.sampleCount > IFNULL(cgroupHour.sampleCount, 0)
        """, arguments: [nowSeconds])
        for row in due {
            let serverKey: Int64 = row["serverKey"]
            let hour: Int64 = row["hour"]
            let samples = try Row.fetchAll(
                database,
                sql: "SELECT startsAt, containers, services FROM cgroupTenSeconds WHERE serverKey = ? AND startsAt >= ? AND startsAt < ?",
                arguments: [serverKey, hour, hour + 3_600]
            ).map(StoredCgroupSample.init(row:))
            let names = try ContainerName.kept(forServer: serverKey, in: database)
            let grouped = samples.map { $0.grouped(names: names) }
            try database.execute(sql: """
            INSERT INTO cgroupHour (serverKey, startsAt, sampleCount, containers, services) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(serverKey, startsAt) DO UPDATE SET
                sampleCount = excluded.sampleCount, containers = excluded.containers, services = excluded.services
            """, arguments: [
                serverKey, hour, samples.count,
                ProcessGroupStorage.encode(CgroupGrouping.top(CgroupGrouping.combined(grouped.map(\.containers)))),
                ProcessGroupStorage.encode(CgroupGrouping.top(CgroupGrouping.combined(grouped.map(\.services)))),
            ])
            let ids = Set(samples.flatMap { $0.containers?.top.map(\.name) ?? [] })
            let touch = try database.cachedStatement(sql: "UPDATE containerName SET seenAt = ? WHERE serverKey = ? AND containerID = ?")
            for id in ids {
                try touch.execute(arguments: [now, serverKey, id])
            }
        }
        return due.count
    }

    /// Times are the servers' clocks, compared with Hive's: a few seconds' difference only moves which
    /// row is pruned this hour rather than the next.
    private func prune(at now: Date, in database: Database) throws -> Int {
        let nowSeconds = Int64(now.timeIntervalSince1970.rounded(.down))
        var pruned = 0
        for table in MetricsTables.all {
            for resolution in MetricsResolution.allCases {
                let oldest = nowSeconds - resolution.keptSeconds
                try database.execute(sql: "DELETE FROM \(table.table(resolution)) WHERE startsAt < ?", arguments: [oldest])
                pruned += database.changesCount
            }
        }
        let oldestProcesses = nowSeconds - Self.processSampleKeptSeconds
        try database.execute(sql: "DELETE FROM processTenSeconds WHERE startsAt < ?", arguments: [oldestProcesses])
        pruned += database.changesCount
        try database.execute(sql: "DELETE FROM processHour WHERE startsAt < ?", arguments: [nowSeconds - Self.processHourKeptSeconds])
        pruned += database.changesCount
        try database.execute(sql: "DELETE FROM cgroupTenSeconds WHERE startsAt < ?", arguments: [nowSeconds - Self.cgroupSampleKeptSeconds])
        pruned += database.changesCount
        try database.execute(sql: "DELETE FROM cgroupHour WHERE startsAt < ?", arguments: [nowSeconds - Self.cgroupHourKeptSeconds])
        pruned += database.changesCount
        let oldestName = now.addingTimeInterval(-Self.containerNameSeconds)
        try database.execute(sql: "DELETE FROM containerName WHERE seenAt < ?", arguments: [oldestName])
        pruned += database.changesCount

        // Every figure kept under a name rolls into its hour table, which keeps them longest.
        for table in MetricsTables.all {
            guard let kind = table.nameKind else { continue }
            try database.execute(sql: """
            DELETE FROM metricsName WHERE kind = ? AND firstSeenAt < ?
                AND NOT EXISTS (SELECT 1 FROM \(table.table(.hour)) WHERE nameID = metricsName.id)
            """, arguments: [kind, now.addingTimeInterval(-Self.newNameSeconds)])
        }
        return pruned
    }
}
