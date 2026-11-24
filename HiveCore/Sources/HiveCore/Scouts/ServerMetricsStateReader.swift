import Foundation
import HiveKit
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
        guard let hasMetrics = try scouts.hasMetrics(serverID) else { return nil }
        guard let scout = try scouts.scout(forServer: serverID) else {
            return ServerMetricsState(hasMetrics: hasMetrics, scout: nil)
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
            clockOffsetSeconds: reported?.clockOffsetSeconds.map(Int.init),
            processesHidden: reported?.processesHidden,
            lastRefusal: reported?.lastRefusal,
            update: update(for: scout)
        )
        return ServerMetricsState(hasMetrics: hasMetrics, scout: state)
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
