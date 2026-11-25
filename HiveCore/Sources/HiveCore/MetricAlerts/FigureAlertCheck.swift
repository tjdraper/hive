import Foundation
import GRDB
import HiveKit
import ScoutProtocol

/// A server's alerts from its figures (§8): filesystems filling, memory short, CPU busy, and restarting.
/// Only a report's newest sample is checked, and only while it's current, so a backlog never opens an
/// alert for the past. Durations count back from that sample through the samples kept, so they're
/// worked out again after a restart, and figures that arrive late are placed when they were taken.
/// The Hive Mac's figures, kept under the Hive's own ID, are checked the same way, against the default
/// limits.
struct FigureAlertCheck: Sendable {
    /// Pages a second, on average over the memory limit's duration.
    static let steadySwapInPages = 50.0
    /// A filesystem's alert ends once it's this far under its limit, or its forecast twice as far off,
    /// so one hovering at the line isn't emailed each time it crosses.
    static let filesystemMargin = 0.05
    /// CPU and memory alerts end once they've been within their limits this long.
    static let clearedAfter: Int64 = 3_600
    /// A restart moves the time the server started by at least its uptime, while its clock being set
    /// right moves it by only the correction.
    static let restartedAfter: Int64 = 5 * 60

    let hiveID: UUID
    let alerts: AlertStore
    let metrics: MetricsDatabase
    let limits: MetricAlertLimitsStore
    let now: @Sendable () -> Date

    /// Returns what it opened and ended.
    @discardableResult
    func check(_ sample: MetricsSample, forServer serverID: UUID) throws -> AlertStore.Applied {
        let limits = serverID == hiveID ? .defaults : try limits.limits(forServer: serverID)
        guard let limits else { return AlertStore.Applied() }
        let open = try alerts.all().map(\.facts).filter { $0.metricAlerts.contains { $0.serverID == serverID } }
        let history = try history(ofServer: serverID, upTo: sample.takenAt, limits: limits)
        // A week of hours changes little from one sample to the next, so it's read once a minute.
        let forecasts = sample.takenAt % 60 == 0 ? try FilesystemForecaster(database: metrics).forecasts(ofServer: serverID) : nil

        var changes = filesystemChanges(sample, forecasts: forecasts, limits: limits, open: open, serverID: serverID)
        changes += memoryChanges(history, at: sample.takenAt, limits: limits, open: open, serverID: serverID)
        changes += cpuChanges(history, at: sample.takenAt, limits: limits, open: open, serverID: serverID)
        let bootedAt = try newBootedAt(of: sample, serverID: serverID)
        if let bootedAt, bootedAt.restarted { changes.append(.open(.serverRestarted(serverID: serverID, bootedAt: bootedAt.at))) }
        // Most samples change nothing, and write nothing to Hive's store.
        guard !changes.isEmpty || bootedAt != nil else { return AlertStore.Applied() }
        let date = now()
        return try alerts.database.writer.write { database in
            if let bootedAt, serverID == hiveID {
                try database.execute(sql: "UPDATE hive SET macBootedAt = ?", arguments: [bootedAt.at])
            } else if let bootedAt {
                try database.execute(sql: "UPDATE scout SET bootedAt = ? WHERE serverID = ?", arguments: [bootedAt.at, serverID])
            }
            return try AlertStore.apply(changes, at: date, in: database)
        }
    }

    private func filesystemChanges(
        _ sample: MetricsSample,
        forecasts: [FilesystemForecast]?,
        limits: MetricAlertLimits,
        open: [AlertFacts],
        serverID: UUID
    ) -> [AlertStore.Change] {
        let limit = Double(limits.filesystemUsedPercent) / 100
        let fillSeconds = Int64(limits.filesystemFillDays) * 86_400
        let openMounts = Set(open.compactMap { facts -> String? in
            guard case .filesystemFilling(_, let mountPoint, _) = facts else { return nil }
            return mountPoint
        })
        var changes = openMounts.subtracting(sample.filesystems.map(\.mountPoint)).map { mountPoint in
            AlertStore.Change.resolve(.filesystemFilling(serverID: serverID, mountPoint: mountPoint), notice: nil)
        }
        for filesystem in sample.filesystems {
            guard let space = filesystem.space else { continue }
            let used = Self.share(space.usedBytes, of: space.usedBytes + space.availableBytes)
            let inodes = space.inodes.flatMap { Self.share($0.used, of: $0.used + $0.free) }
            let fillsIn = forecasts?.first { $0.mountPoint == filesystem.mountPoint }?.fillsAt.map { $0 - sample.takenAt }
            let condition = AlertCondition.filesystemFilling(serverID: serverID, mountPoint: filesystem.mountPoint)

            if openMounts.contains(filesystem.mountPoint) {
                let isUnder = [used, inodes].allSatisfy { ($0 ?? 0) < limit - Self.filesystemMargin }
                // Unknown between the minutes the forecast is read in.
                let fillsLater = forecasts != nil && (fillsIn.map { $0 > 2 * fillSeconds } ?? true)
                if isUnder, fillsLater { changes.append(.resolve(condition, notice: nil)) }
                continue
            }
            let reading = FilesystemReading(
                usedShare: used.flatMap { $0 > limit ? $0 : nil },
                inodesUsedShare: inodes.flatMap { $0 > limit ? $0 : nil },
                fillsAt: fillsIn.flatMap { $0 <= fillSeconds ? sample.takenAt + $0 : nil }
            )
            if reading.usedShare != nil || reading.inodesUsedShare != nil || reading.fillsAt != nil {
                changes.append(.open(.filesystemFilling(serverID: serverID, mountPoint: filesystem.mountPoint, reading: reading)))
            }
        }
        return changes
    }

    private static func share(_ part: UInt64, of whole: UInt64) -> Double? {
        whole > 0 ? Double(part) / Double(whole) : nil
    }

    private struct ServerHistory {
        let availableShare: FigureHistory
        let swapInPages: FigureHistory
        let busyShare: FigureHistory
        let stealShare: FigureHistory
        let loadPerCore: FigureHistory
    }

    /// Enough samples for the longest duration and the hour before an alert ends.
    private func history(ofServer serverID: UUID, upTo end: Int64, limits: MetricAlertLimits) throws -> ServerHistory {
        let start = end - Int64(max(limits.memoryMinutes, limits.cpuMinutes)) * 60 - Self.clearedAfter
        let rows = try metrics.writer.read { database in
            try Row.fetchAll(database, sql: """
            SELECT startsAt, memoryAvailable * 1.0 / NULLIF(memoryTotal, 0) AS availableShare, swapInPages,
                cpuUser + cpuSystem + IFNULL(cpuIOWait, 0) + IFNULL(cpuSteal, 0) AS busyShare, cpuSteal,
                loadOneMinute / NULLIF(cores, 0) AS loadPerCore
            FROM serverTenSeconds
            JOIN metricsServer ON metricsServer.id = serverTenSeconds.serverKey
            WHERE metricsServer.serverID = ? AND startsAt > ? AND startsAt <= ?
            ORDER BY startsAt
            """, arguments: [serverID, start, end])
        }
        func figure(_ column: String) -> FigureHistory {
            FigureHistory(samples: rows.compactMap { row in (row[column] as Double?).map { (row["startsAt"], $0) } })
        }
        return ServerHistory(
            availableShare: figure("availableShare"),
            swapInPages: figure("swapInPages"),
            busyShare: figure("busyShare"),
            stealShare: figure("cpuSteal"),
            loadPerCore: figure("loadPerCore")
        )
    }

    private func memoryChanges(
        _ history: ServerHistory,
        at end: Int64,
        limits: MetricAlertLimits,
        open: [AlertFacts],
        serverID: UUID
    ) -> [AlertStore.Change] {
        let duration = Int64(limits.memoryMinutes) * 60
        let availableLimit = Double(limits.memoryAvailablePercent) / 100
        let isShort: (Double) -> Bool = { $0 < availableLimit }
        let isSwapping: (Double) -> Bool = { $0 > Self.steadySwapInPages }

        let isOpen = open.contains { if case .memoryShort = $0 { true } else { false } }
        if isOpen {
            let cleared = history.availableShare.hasCleared(isShort, over: duration, for: Self.clearedAfter, upTo: end)
                && history.swapInPages.hasCleared(isSwapping, over: duration, for: Self.clearedAfter, upTo: end)
            return cleared ? [.resolve(.memoryShort(serverID: serverID), notice: nil)] : []
        }
        let reading = MemoryReading(
            availableShare: history.availableShare.average(over: duration, upTo: end).flatMap { isShort($0) ? $0 : nil },
            swapInPagesPerSecond: history.swapInPages.average(over: duration, upTo: end).flatMap { isSwapping($0) ? $0 : nil },
            minutes: limits.memoryMinutes
        )
        guard reading.availableShare != nil || reading.swapInPagesPerSecond != nil else { return [] }
        return [.open(.memoryShort(serverID: serverID, reading: reading))]
    }

    private func cpuChanges(
        _ history: ServerHistory,
        at end: Int64,
        limits: MetricAlertLimits,
        open: [AlertFacts],
        serverID: UUID
    ) -> [AlertStore.Change] {
        let duration = Int64(limits.cpuMinutes) * 60
        let figures: [(history: FigureHistory, isOver: (Double) -> Bool)] = [
            (history.busyShare, { $0 > Double(limits.cpuBusyPercent) / 100 }),
            (history.stealShare, { $0 > Double(limits.cpuStealPercent) / 100 }),
            (history.loadPerCore, { $0 > limits.loadPerCore }),
        ]

        let isOpen = open.contains { if case .cpuBusy = $0 { true } else { false } }
        if isOpen {
            let cleared = figures.allSatisfy { $0.history.hasCleared($0.isOver, over: duration, for: Self.clearedAfter, upTo: end) }
            return cleared ? [.resolve(.cpuBusy(serverID: serverID), notice: nil)] : []
        }
        let over = figures.map { figure in
            figure.history.average(over: duration, upTo: end).flatMap { figure.isOver($0) ? $0 : nil }
        }
        guard over.contains(where: { $0 != nil }) else { return [] }
        let reading = CPUReading(busyShare: over[0], stealShare: over[1], loadPerCore: over[2], minutes: limits.cpuMinutes)
        return [.open(.cpuBusy(serverID: serverID, reading: reading))]
    }

    /// When the server started, if that's moved since it was last noted, and whether it restarted. The
    /// time is noted in the same transaction as the notice, so each restart is emailed once. The first
    /// time a Scout reports, or Hive reads its Mac, there's nothing to compare with.
    private func newBootedAt(of sample: MetricsSample, serverID: UUID) throws -> (at: Int64, restarted: Bool)? {
        guard let uptime = sample.server.uptimeSeconds else { return nil }
        let isHiveMac = serverID == hiveID
        let noted: Int64?? = try alerts.database.writer.read { database in
            if isHiveMac { return .some(try Int64.fetchOne(database, sql: "SELECT macBootedAt FROM hive")) }
            return try ScoutRecord.filter(Column("serverID") == serverID).fetchOne(database).map(\.bootedAt)
        }
        // A server without a Scout.
        guard let noted else { return nil }
        let bootedAt = sample.takenAt - Int64(uptime.rounded())
        if let noted, abs(bootedAt - noted) <= Self.restartedAfter { return nil }
        return (bootedAt, noted.map { bootedAt > $0 } ?? false)
    }
}
