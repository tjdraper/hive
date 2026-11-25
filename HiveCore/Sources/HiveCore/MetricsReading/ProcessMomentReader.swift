import Foundation
import GRDB
import HiveKit
import ScoutProtocol

/// A server's processes at a moment chosen on a chart: the sample nearest it, while samples are kept,
/// and otherwise its hour's busiest groups (§6).
struct ProcessMomentReader: Sendable {
    /// Further than this, the nearest sample would show another moment than the one chosen, such as
    /// before a Scout stopped reporting.
    static let nearestSampleSeconds: Int64 = 5 * 60

    let database: MetricsDatabase

    /// `moment` is seconds since 1970 on the server's clock.
    func processes(ofServer serverID: UUID, at moment: Int64) throws -> ProcessMoment {
        try database.writer.read { database in
            let serverKey = try Int64.fetchOne(database, sql: "SELECT id FROM metricsServer WHERE serverID = ?", arguments: [serverID])
            guard let serverKey else { return .notKept }

            if let row = try Row.fetchOne(database, sql: """
            SELECT startsAt, groups FROM processTenSeconds
            WHERE serverKey = ? AND startsAt BETWEEN ? AND ?
            ORDER BY ABS(startsAt - ?), startsAt LIMIT 1
            """, arguments: [serverKey, moment - Self.nearestSampleSeconds, moment + Self.nearestSampleSeconds, moment]) {
                let groups = try ProcessGroupStorage.decode([ProcessGroup].self, from: row["groups"])
                let names = try ContainerName.kept(forServer: serverKey, in: database)
                return .sample(takenAt: row["startsAt"], groups: groups.map { ProcessGroupFigures($0, names: names) })
            }

            let hour = MetricsResolution.hour.periodStart(of: moment)
            if let blob = try Data.fetchOne(
                database,
                sql: "SELECT groups FROM processHour WHERE serverKey = ? AND startsAt = ?",
                arguments: [serverKey, hour]
            ) {
                let groups = try ProcessGroupStorage.decode([HourlyProcessGroup].self, from: blob)
                let names = try ContainerName.kept(forServer: serverKey, in: database)
                return .hour(startsAt: hour, groups: groups.map { HourlyProcessGroupFigures($0, names: names) })
            }
            return .notKept
        }
    }
}

private extension ProcessGroupPlace {
    init?(containerID: String?, service: String?, names: [String: ContainerName]) {
        guard containerID != nil || service != nil else { return nil }
        let group = containerID.map { CgroupGroupKey.container($0, named: names[$0]) }
        self.init(containerID: containerID, containerGroup: group?.name, composeProject: group?.composeProject, service: service)
    }
}

private extension ProcessGroupFigures {
    init(_ group: ProcessGroup, names: [String: ContainerName]) {
        self.init(
            command: group.command,
            user: group.user,
            place: ProcessGroupPlace(containerID: group.containerID, service: group.service, names: names),
            count: group.count,
            cpuCores: group.cpuCores,
            ownMemoryBytes: group.ownMemoryBytes
        )
    }
}

private extension HourlyProcessGroupFigures {
    init(_ group: HourlyProcessGroup, names: [String: ContainerName]) {
        self.init(
            command: group.command,
            user: group.user,
            place: ProcessGroupPlace(containerID: group.containerID, service: group.service, names: names),
            highestCount: group.highestCount,
            averageCPUCores: group.averageCPUCores,
            highestCPUCores: group.highestCPUCores,
            averageOwnMemoryBytes: group.averageOwnMemoryBytes,
            highestOwnMemoryBytes: group.highestOwnMemoryBytes
        )
    }
}
