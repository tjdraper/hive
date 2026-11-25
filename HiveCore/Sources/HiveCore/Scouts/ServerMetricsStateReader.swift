import Foundation
import GRDB
import HiveKit
import ScoutCore
import ScoutProtocol

/// A server's metrics state for Beekeeper: whether it has metrics, and its Scout as it last signed in
/// and reported, with whether it's out of date.
struct ServerMetricsStateReader: Sendable {
    let scouts: ScoutStore
    let metrics: MetricsStore
    /// The release of Scout Hive.app carries. Hive's own version plays no part, so a release of Hive
    /// that leaves Scout alone doesn't ask for every server's Scout to be updated.
    let carriedScoutVersion: String?

    /// Nil when there's no such server.
    func state(ofServer serverID: UUID) throws -> ServerMetricsState? {
        let alerts = try AlertStore(database: scouts.database).all().flatMap(\.facts.metricAlerts)
            .filter { $0.serverID == serverID }
            .map(\.alert)
        if let state = try hiveMacState(serverID, alerts: alerts) { return state }
        guard let hasMetrics = try scouts.hasMetrics(serverID) else { return nil }
        guard let scout = try scouts.scout(forServer: serverID) else {
            return ServerMetricsState(hasMetrics: hasMetrics, scout: nil, alerts: alerts)
        }
        // What the server reported before this Scout enrolled may be another Scout's, or another machine's.
        let reported = try metrics.server(serverID).flatMap { record in
            record.lastReportAt.map { $0 >= scout.enrolledAt } == true ? record : nil
        }
        let state = ScoutState(
            enrolledAt: scout.enrolledAt,
            lastSeenAt: [scout.lastSeenAt, reported?.lastReportAt].compactMap(\.self).max(),
            lastReportAt: reported?.lastReportAt,
            version: scout.version,
            platform: scout.platform,
            distribution: reported?.distribution,
            kernel: reported?.kernel,
            startedAt: reported.flatMap { record in
                guard let takenAt = record.lastSampleAt, let uptime = record.uptimeSeconds else { return nil }
                return takenAt - Int64(uptime.rounded())
            },
            clockOffsetSeconds: reported?.clockOffsetSeconds.map(Int.init),
            processesHidden: reported?.processesHidden,
            lastRefusal: reported?.lastRefusal,
            update: update(for: scout)
        )
        return ServerMetricsState(hasMetrics: hasMetrics, scout: state, alerts: alerts)
    }

    /// The Hive Mac's, when `id` is the Hive's own. Hive reads it with the readers of the Scout it's built
    /// with, so that's its version, and it's "enrolled" from when the Hive was set up.
    private func hiveMacState(_ id: UUID, alerts: [MetricAlert]) throws -> ServerMetricsState? {
        let hive = try scouts.database.writer.read { database in
            try Row.fetchOne(database, sql: "SELECT createdAt, collectsMacMetrics FROM hive WHERE id = ?", arguments: [id])
        }
        guard let hive else { return nil }
        let reported = try metrics.server(id)
        let state = ScoutState(
            enrolledAt: hive["createdAt"],
            lastSeenAt: reported?.lastReportAt,
            lastReportAt: reported?.lastReportAt,
            version: ScoutRelease.version.description,
            platform: ScoutRelease.platform,
            distribution: reported?.distribution,
            kernel: reported?.kernel,
            startedAt: reported.flatMap { record in
                guard let takenAt = record.lastSampleAt, let uptime = record.uptimeSeconds else { return nil }
                return takenAt - Int64(uptime.rounded())
            },
            clockOffsetSeconds: 0,
            processesHidden: false,
            lastRefusal: reported?.lastRefusal,
            update: nil
        )
        return ServerMetricsState(hasMetrics: hive["collectsMacMetrics"], scout: state, alerts: alerts)
    }

    private func update(for scout: ScoutRecord) -> ScoutUpdate? {
        if let protocolVersion = scout.protocolVersion, !ScoutProtocolVersion.isAccepted(protocolVersion) {
            return .protocolNotAccepted
        }
        guard let carriedScoutVersion,
              let carried = ScoutVersion(parsing: carriedScoutVersion),
              let installed = scout.version.flatMap(ScoutVersion.init(parsing:)),
              installed < carried
        else { return nil }
        return .newerRelease(version: carried.description)
    }
}
