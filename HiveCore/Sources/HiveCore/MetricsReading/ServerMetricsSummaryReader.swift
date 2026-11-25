import Foundation
import GRDB
import HiveKit
import ScoutProtocol

/// Every server with metrics, for the dashboard: whether it's reporting, its newest figures and its
/// last hour.
struct ServerMetricsSummaryReader: Sendable {
    /// No figures for this long means the server stopped reporting (§8).
    static let stoppedAfter: TimeInterval = 3 * 60

    let scouts: ScoutStore
    let database: MetricsDatabase
    let now: @Sendable () -> Date

    func summaries() throws -> [ServerMetricsSummary] {
        let servers = try scouts.serversWithMetrics()
        let alerts = Dictionary(grouping: try AlertStore(database: scouts.database).all().flatMap(\.facts.metricAlerts), by: \.serverID)
        let now = now()
        return try database.writer.read { database in
            try servers.map { serverID, scout in
                let record = try MetricsServerRecord.filter(Column("serverID") == serverID).fetchOne(database)
                let latest = try record.flatMap { try Self.latest(of: $0, in: database) }
                return ServerMetricsSummary(
                    serverID: serverID,
                    reporting: Self.reporting(record, scout: scout, at: now),
                    lastReportAt: record?.lastReportAt,
                    latest: latest,
                    lastHour: try record.map { try Self.lastHour(of: $0, at: now, in: database) } ?? [],
                    alerts: alerts[serverID, default: []].map(\.alert)
                )
            }
        }
    }

    /// The server's newest sample, as kept, or nil before it has one.
    static func latest(ofServer serverID: UUID, in metrics: MetricsDatabase) throws -> ServerMetricsLatest? {
        try metrics.writer.read { database in
            try MetricsServerRecord.filter(Column("serverID") == serverID).fetchOne(database).flatMap { try latest(of: $0, in: database) }
        }
    }

    private static func reporting(_ record: MetricsServerRecord?, scout: ScoutRecord?, at now: Date) -> MetricsReporting {
        // What the server reported before its Scout enrolled may be another Scout's, or another machine's.
        guard let scout, let lastReportAt = record?.lastReportAt, lastReportAt >= scout.enrolledAt else { return .waiting }
        if now.timeIntervalSince(lastReportAt) > stoppedAfter { return .stopped }
        switch record?.lastRefusal {
        case nil: return .reporting
        case ScoutRefusal.Reason.clockAhead.rawValue: return .clockAhead
        default: return .refused
        }
    }

    private static func latest(of record: MetricsServerRecord, in database: Database) throws -> ServerMetricsLatest? {
        guard let serverKey = record.id,
              let row = try Row.fetchOne(database, sql: """
              SELECT * FROM serverTenSeconds WHERE serverKey = ? ORDER BY startsAt DESC LIMIT 1
              """, arguments: [serverKey])
        else { return nil }
        let takenAt: Int64 = row["startsAt"]

        let filesystems = try Row.fetchAll(database, sql: """
        SELECT metricsName.name, size, used, available FROM filesystemTenSeconds
        JOIN metricsName ON metricsName.id = filesystemTenSeconds.nameID
        WHERE metricsName.serverKey = ? AND startsAt = ? AND size IS NOT NULL AND used IS NOT NULL AND available IS NOT NULL
        """, arguments: [serverKey, takenAt]).map { row in
            FilesystemUse(mountPoint: row["name"], sizeBytes: row["size"], usedBytes: row["used"], availableBytes: row["available"])
        }

        var cpu: CPUShares?
        if let user: Double = row["cpuUser"], let system: Double = row["cpuSystem"],
           let ioWait: Double = row["cpuIOWait"], let steal: Double = row["cpuSteal"] {
            cpu = CPUShares(user: user, system: system, ioWait: ioWait, steal: steal)
        }
        var load: LoadFigures?
        if let one: Double = row["loadOneMinute"], let five: Double = row["loadFiveMinutes"],
           let fifteen: Double = row["loadFifteenMinutes"] {
            load = LoadFigures(oneMinute: one, fiveMinutes: five, fifteenMinutes: fifteen)
        }
        var memory: MemoryUse?
        if let total: UInt64 = row["memoryTotal"], let available: UInt64 = row["memoryAvailable"],
           let swapTotal: UInt64 = row["swapTotal"], let swapUsed: UInt64 = row["swapUsed"] {
            memory = MemoryUse(totalBytes: total, availableBytes: available, swapTotalBytes: swapTotal, swapUsedBytes: swapUsed)
        }
        let cgroups = try CgroupMomentReader.sample(at: takenAt, serverKey: serverKey, in: database)
        return ServerMetricsLatest(
            serverID: record.serverID,
            takenAt: takenAt,
            cores: row["cores"],
            cpu: cpu,
            load: load,
            memory: memory,
            fullestFilesystem: filesystems.max { $0.usedShare < $1.usedShare },
            containers: cgroups.containers,
            services: cgroups.services
        )
    }

    /// Each minute of the hour up to now on the server's clock, so a server that stopped has none
    /// after it stopped rather than an hour that looks current.
    private static func lastHour(of record: MetricsServerRecord, at now: Date, in database: Database) throws -> [MetricsSparkPoint] {
        guard let serverKey = record.id else { return [] }
        let end = Int64(now.timeIntervalSince1970.rounded(.down)) + (record.clockOffsetSeconds ?? 0)
        return try Row.fetchAll(database, sql: """
        SELECT startsAt, cpuUser + cpuSystem + cpuIOWait + cpuSteal AS cpuBusy,
            1.0 - memoryAvailable * 1.0 / NULLIF(memoryTotal, 0) AS memoryUsed
        FROM serverMinute WHERE serverKey = ? AND startsAt > ? AND startsAt <= ?
        ORDER BY startsAt
        """, arguments: [serverKey, end - 3_600, end]).map { row in
            MetricsSparkPoint(startsAt: row["startsAt"], cpuBusy: row["cpuBusy"], memoryUsed: row["memoryUsed"])
        }
    }
}
