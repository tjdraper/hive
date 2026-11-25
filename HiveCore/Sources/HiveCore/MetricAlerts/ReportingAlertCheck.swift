import Foundation
import GRDB
import ScoutProtocol

/// Whether each server with metrics is reporting (§8), from when Hive last heard from it: stopped, alone
/// or with others, or refused for its clock. Also ends a server's metric alerts once its metrics, or the
/// server, are removed.
struct ReportingAlertCheck: Sendable {
    static let stoppedAfter = ServerMetricsSummaryReader.stoppedAfter
    /// Servers whose last reports are this close together stopped together.
    static let togetherWithin: TimeInterval = 60
    /// A server quiet this long may be stopping too, so servers that stopped with it wait for it rather
    /// than being emailed about alone.
    static let quietAfter: TimeInterval = 30

    private struct Watched {
        let lastReportAt: Date
        let lastRefusal: String?
        let clockOffsetSeconds: Int64?
    }

    let scouts: ScoutStore
    let metrics: MetricsDatabase

    /// `inGrace` while Scouts may still be backing off, such as just after Hive starts: no server is taken
    /// for stopped, though one reporting again still ends its alert.
    func changes(open: [AlertRecord], at now: Date, inGrace: Bool) throws -> [AlertStore.Change] {
        let servers = try watched()
        let hasMetrics = try Set(scouts.serversWithMetrics().compactMap { $0.scout == nil ? nil : $0.serverID })
        let opened = open.map(\.facts)
        var changes = opened.flatMap { ended($0, servers: servers, hasMetrics: hasMetrics) }
        if !inGrace { changes += stopped(servers, opened: opened, at: now) }
        for (serverID, server) in servers where server.lastRefusal == ScoutRefusal.Reason.clockAhead.rawValue {
            guard now.timeIntervalSince(server.lastReportAt) <= Self.stoppedAfter else { continue }
            changes.append(.open(.clockAhead(serverID: serverID, offsetSeconds: server.clockOffsetSeconds)))
        }
        return changes
    }

    /// Servers with a Scout that has reported since it enrolled, by what Hive last heard from them.
    private func watched() throws -> [UUID: Watched] {
        let enrolled = try scouts.serversWithMetrics().compactMap { server in server.scout.map { (server.serverID, $0.enrolledAt) } }
        return try metrics.writer.read { database in
            var watched: [UUID: Watched] = [:]
            for (serverID, enrolledAt) in enrolled {
                // What the server reported before this Scout enrolled may be another Scout's, or another machine's.
                guard let record = try MetricsServerRecord.filter(Column("serverID") == serverID).fetchOne(database),
                      let lastReportAt = record.lastReportAt, lastReportAt >= enrolledAt
                else { continue }
                watched[serverID] = Watched(
                    lastReportAt: lastReportAt,
                    lastRefusal: record.lastRefusal,
                    clockOffsetSeconds: record.clockOffsetSeconds
                )
            }
            return watched
        }
    }

    /// A stopped server's alert ends with a notice once it reports again, and without one once its
    /// metrics are removed. Servers that stopped together have one notice, once none is still stopped.
    private func ended(_ facts: AlertFacts, servers: [UUID: Watched], hasMetrics: Set<UUID>) -> [AlertStore.Change] {
        func reportedAgain(_ server: StoppedServer) -> Date? {
            servers[server.serverID].flatMap { $0.lastReportAt > server.lastReportAt ? $0.lastReportAt : nil }
        }
        switch facts {
        case .stoppedReporting(let server):
            let condition = AlertCondition.stoppedReporting(serverID: server.serverID)
            if let reportedAt = reportedAgain(server) {
                return [.resolve(condition, notice: .reportingAgain(serverIDs: [server.serverID], since: reportedAt))]
            }
            return hasMetrics.contains(server.serverID) ? [] : [.resolve(condition, notice: nil)]
        case .stoppedTogether(let stopped):
            let stillStopped = stopped.filter { hasMetrics.contains($0.serverID) && reportedAgain($0) == nil }
            guard stillStopped.isEmpty else { return [] }
            let back = stopped.compactMap { server in reportedAgain(server).map { (serverID: server.serverID, at: $0) } }
            let notice = back.map(\.at).min().map { AlertFacts.reportingAgain(serverIDs: back.map(\.serverID), since: $0) }
            return [.resolve(.stoppedTogether(serverIDs: stopped.map(\.serverID)), notice: notice)]
        case .clockAhead(let serverID, _):
            guard servers[serverID]?.lastRefusal != ScoutRefusal.Reason.clockAhead.rawValue else { return [] }
            return [.resolve(.clockAhead(serverID: serverID), notice: nil)]
        case .filesystemFilling(let serverID, _, _), .memoryShort(let serverID, _), .cpuBusy(let serverID, _):
            guard !hasMetrics.contains(serverID), let condition = facts.condition else { return [] }
            return [.resolve(condition, notice: nil)]
        default:
            return []
        }
    }

    /// Servers that stopped within `togetherWithin` of each other are one alert. Nothing is opened while
    /// a server that's gone quiet might still turn out to have stopped with them.
    private func stopped(_ servers: [UUID: Watched], opened: [AlertFacts], at now: Date) -> [AlertStore.Change] {
        let covered = Set(opened.flatMap { facts -> [UUID] in
            switch facts {
            case .stoppedReporting(let server): [server.serverID]
            case .stoppedTogether(let servers): servers.map(\.serverID)
            default: []
            }
        })
        let uncovered = servers.filter { !covered.contains($0.key) }
        let silent = uncovered.mapValues { now.timeIntervalSince($0.lastReportAt) }
        let newlyStopped = uncovered
            .filter { silent[$0.key, default: 0] > Self.stoppedAfter }
            .map { StoppedServer(serverID: $0.key, lastReportAt: $0.value.lastReportAt) }
            .sorted { $0.lastReportAt < $1.lastReportAt }
        guard !newlyStopped.isEmpty else { return [] }

        let quiet = uncovered
            .filter { (Self.quietAfter ... Self.stoppedAfter).contains(silent[$0.key, default: 0]) }
            .map(\.value.lastReportAt)
        let mayJoin = quiet.contains { quietAt in
            newlyStopped.contains { abs($0.lastReportAt.timeIntervalSince(quietAt)) <= Self.togetherWithin }
        }
        guard !mayJoin else { return [] }

        var groups: [[StoppedServer]] = []
        for server in newlyStopped {
            if let last = groups.last?.last, server.lastReportAt.timeIntervalSince(last.lastReportAt) <= Self.togetherWithin {
                groups[groups.count - 1].append(server)
            } else {
                groups.append([server])
            }
        }
        return groups.map { group in
            .open(group.count == 1 ? .stoppedReporting(group[0]) : .stoppedTogether(group))
        }
    }
}
