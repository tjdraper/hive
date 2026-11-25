import Foundation
import GRDB
import HiveKit
import ScoutProtocol

/// A server's containers and services at a moment chosen on a chart: the sample nearest it while
/// samples are kept, and otherwise its hour's busiest (§6). Containers are grouped with the names Hive
/// knows now, so one named after its sample was taken still shows by name.
struct CgroupMomentReader: Sendable {
    let database: MetricsDatabase

    /// `moment` is seconds since 1970 on the server's clock.
    func cgroups(ofServer serverID: UUID, at moment: Int64) throws -> CgroupMoment {
        try database.writer.read { database in
            let serverKey = try Int64.fetchOne(database, sql: "SELECT id FROM metricsServer WHERE serverID = ?", arguments: [serverID])
            guard let serverKey else { return .notKept }

            let nearest = ProcessMomentReader.nearestSampleSeconds
            if let row = try Row.fetchOne(database, sql: """
            SELECT startsAt, containers, services FROM cgroupTenSeconds
            WHERE serverKey = ? AND startsAt BETWEEN ? AND ?
            ORDER BY ABS(startsAt - ?), startsAt LIMIT 1
            """, arguments: [serverKey, moment - nearest, moment + nearest, moment]) {
                let sample = try StoredCgroupSample(row: row)
                let grouped = sample.grouped(names: try ContainerName.kept(forServer: serverKey, in: database))
                return .sample(
                    takenAt: sample.startsAt,
                    containerCount: sample.containers?.count ?? 0,
                    serviceCount: sample.services?.count ?? 0,
                    containers: grouped.containers,
                    services: grouped.services
                )
            }

            let hour = MetricsResolution.hour.periodStart(of: moment)
            if let row = try Row.fetchOne(
                database,
                sql: "SELECT startsAt, sampleCount, containers, services FROM cgroupHour WHERE serverKey = ? AND startsAt = ?",
                arguments: [serverKey, hour]
            ) {
                let stored = try StoredCgroupHour(row: row)
                return .hour(startsAt: hour, containers: stored.containers.map(\.figures), services: stored.services.map(\.figures))
            }
            return .notKept
        }
    }

    /// The server's containers and services in the sample taken at `takenAt`, for live updates.
    static func sample(at takenAt: Int64, serverKey: Int64, in database: Database) throws -> (
        containers: [CgroupGroupFigures]?,
        services: [CgroupGroupFigures]?
    ) {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT startsAt, containers, services FROM cgroupTenSeconds WHERE serverKey = ? AND startsAt = ?",
            arguments: [serverKey, takenAt]
        ) else { return (nil, nil) }
        let sample = try StoredCgroupSample(row: row)
        let grouped = sample.grouped(names: try ContainerName.kept(forServer: serverKey, in: database))
        return (sample.containers.map { _ in grouped.containers }, sample.services.map { _ in grouped.services })
    }
}
