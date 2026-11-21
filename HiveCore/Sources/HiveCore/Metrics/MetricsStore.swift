import Foundation
import GRDB
import ScoutProtocol

enum MetricsKeepOutcome: Equatable {
    case kept(samples: Int, minutes: Int)
    case refused(ScoutRefusal.Reason)
}

/// Keeps what Scouts send in the metrics database: one sample per server and time, each minute and
/// hour worked out again as samples land in it, and what each server last said about itself.
struct MetricsStore: Sendable {
    let database: MetricsDatabase

    /// Records the request, with the server's clock offset, then keeps what passes
    /// `MetricsReportCheck`, all in one transaction.
    func keep(_ report: MetricsReport, forServer serverID: UUID, at now: Date) throws -> MetricsKeepOutcome {
        let nowSeconds = Int64(now.timeIntervalSince1970.rounded(.down))
        return try database.writer.write { database in
            var server = try MetricsServerRecord.find(serverID, in: database)
            server.lastReportAt = now
            server.clockOffsetSeconds = report.sentAt - nowSeconds

            let outcome: MetricsKeepOutcome
            switch MetricsReportCheck.checked(report, at: nowSeconds) {
            case .refused(let reason):
                outcome = .refused(reason)
            case .accepted(let kept):
                outcome = try keep(kept, for: &server, at: now, in: database)
            }
            if case .refused(let reason) = outcome {
                server.lastRefusal = reason.rawValue
                server.lastRefusedAt = now
            } else {
                server.lastRefusal = nil
            }
            try server.update(database)
            return outcome
        }
    }

    /// Records a refusal of a request that never reached `keep`, such as one too large to read.
    func recordRefusal(_ reason: ScoutRefusal.Reason, forServer serverID: UUID, at now: Date) throws {
        try database.writer.write { database in
            var server = try MetricsServerRecord.find(serverID, in: database)
            server.lastReportAt = now
            server.lastRefusal = reason.rawValue
            server.lastRefusedAt = now
            try server.update(database)
        }
    }

    /// Removes everything kept for the server, as when it's removed from Hive.
    func remove(forServer serverID: UUID) throws {
        try database.writer.write { database in
            _ = try MetricsServerRecord.filter(Column("serverID") == serverID).deleteAll(database)
        }
    }

    func server(_ serverID: UUID) throws -> MetricsServerRecord? {
        try database.writer.read { try MetricsServerRecord.filter(Column("serverID") == serverID).fetchOne($0) }
    }

    private func keep(
        _ report: MetricsReport,
        for server: inout MetricsServerRecord,
        at now: Date,
        in database: Database
    ) throws -> MetricsKeepOutcome {
        guard let serverKey = server.id else { return .kept(samples: 0, minutes: 0) }
        var names = try MetricsNames(serverKey: serverKey, in: database)
        guard try names.admit(report, at: now, in: database) else { return .refused(.tooManyNewNames) }

        var minutes = Set<Int64>()
        var hours = Set<Int64>()
        for sample in report.samples {
            let startsAt = MetricsResolution.tenSeconds.periodStart(of: sample.takenAt)
            try insert(sample, at: (serverKey, startsAt), names: names, in: database)
            server.recordFacts(of: sample)
            minutes.insert(MetricsResolution.minute.periodStart(of: startsAt))
            hours.insert(MetricsResolution.hour.periodStart(of: startsAt))
        }
        if let newest = report.samples.max(by: { $0.takenAt < $1.takenAt }) {
            try names.recordFilesystems(of: newest, in: database)
        }
        for minute in report.minutes {
            let startsAt = MetricsResolution.minute.periodStart(of: minute.startsAt)
            try insert(minute, at: (serverKey, startsAt), names: names, in: database)
            hours.insert(MetricsResolution.hour.periodStart(of: startsAt))
        }

        for table in MetricsTables.all {
            for minute in minutes {
                try MetricsRollup.rollUp(table, to: .minute, startingAt: minute, serverKey: serverKey, in: database)
            }
            for hour in hours {
                try MetricsRollup.rollUp(table, to: .hour, startingAt: hour, serverKey: serverKey, in: database)
            }
        }
        return .kept(samples: report.samples.count, minutes: report.minutes.count)
    }

    private func insert(_ sample: MetricsSample, at row: MetricsRollup.Row, names: MetricsNames, in database: Database) throws {
        let startsAt = row.startsAt
        let serverWide = ServerWideFigures(cpu: sample.cpu, memory: sample.memory, pressure: sample.pressure, processes: sample.processes)
        try MetricsRollup.insertSample(MetricsTables.server.values(of: serverWide), into: MetricsTables.server, at: row, in: database)
        for filesystem in sample.filesystems {
            guard let id = names.id(MetricsTables.filesystemKind, filesystem.mountPoint) else { continue }
            let values = MetricsTables.filesystem.values(of: filesystem)
            try MetricsRollup.insertSample(values, into: MetricsTables.filesystem, at: (id, startsAt), in: database)
        }
        for disk in sample.disks {
            guard let id = names.id(MetricsTables.diskKind, disk.name) else { continue }
            try MetricsRollup.insertSample(MetricsTables.disk.values(of: disk), into: MetricsTables.disk, at: (id, startsAt), in: database)
        }
        for interface in sample.networkInterfaces {
            guard let id = names.id(MetricsTables.networkInterfaceKind, interface.name) else { continue }
            let values = MetricsTables.networkInterface.values(of: interface)
            try MetricsRollup.insertSample(values, into: MetricsTables.networkInterface, at: (id, startsAt), in: database)
        }
        if let processes = sample.processes {
            try database.cachedStatement(sql: """
            INSERT INTO processTenSeconds (serverKey, startsAt, groups) VALUES (?, ?, ?) ON CONFLICT DO NOTHING
            """).execute(arguments: [row.key, startsAt, ProcessGroupStorage.encode(processes.groups)])
        }
    }

    /// A minute Scout folded from samples it held. Each name's highest and lowest are matched to its
    /// average by name, since a name may be missing from either.
    private func insert(_ minute: MetricsMinute, at row: MetricsRollup.Row, names: MetricsNames, in database: Database) throws {
        let startsAt = row.startsAt
        let (average, highest, lows) = (minute.average, minute.highest, minute.lowest)
        let count = minute.sampleCount

        var lowestMemory = average.memory
        if let available = lows.memoryAvailableBytes { lowestMemory?.availableBytes = available }
        let serverValues = MetricsTables.server.values(
            average: ServerWideFigures(cpu: average.cpu, memory: average.memory, pressure: average.pressure),
            highest: ServerWideFigures(cpu: highest.cpu, memory: highest.memory, pressure: highest.pressure),
            lowest: ServerWideFigures(cpu: average.cpu, memory: lowestMemory, pressure: average.pressure)
        )
        try MetricsRollup.insertMinute(serverValues, into: MetricsTables.server, at: row, sampleCount: count, in: database)

        for filesystem in average.filesystems {
            guard let id = names.id(MetricsTables.filesystemKind, filesystem.mountPoint) else { continue }
            var lowest = filesystem
            if let low = lows.filesystems.first(where: { $0.mountPoint == filesystem.mountPoint }) {
                lowest.space?.availableBytes = low.availableBytes
                if let free = low.inodesFree { lowest.space?.inodes?.free = free }
            }
            let values = MetricsTables.filesystem.values(
                average: filesystem,
                highest: highest.filesystems.first { $0.mountPoint == filesystem.mountPoint } ?? filesystem,
                lowest: lowest
            )
            try MetricsRollup.insertMinute(values, into: MetricsTables.filesystem, at: (id, startsAt), sampleCount: count, in: database)
        }
        for disk in average.disks {
            guard let id = names.id(MetricsTables.diskKind, disk.name) else { continue }
            let highestDisk = highest.disks.first { $0.name == disk.name } ?? disk
            let values = MetricsTables.disk.values(average: disk, highest: highestDisk, lowest: disk)
            try MetricsRollup.insertMinute(values, into: MetricsTables.disk, at: (id, startsAt), sampleCount: count, in: database)
        }
        for interface in average.networkInterfaces {
            guard let id = names.id(MetricsTables.networkInterfaceKind, interface.name) else { continue }
            let values = MetricsTables.networkInterface.values(
                average: interface,
                highest: highest.networkInterfaces.first { $0.name == interface.name } ?? interface,
                lowest: interface
            )
            let table = MetricsTables.networkInterface
            try MetricsRollup.insertMinute(values, into: table, at: (id, startsAt), sampleCount: count, in: database)
        }
    }
}
