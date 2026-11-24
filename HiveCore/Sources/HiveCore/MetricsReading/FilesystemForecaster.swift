import Foundation
import GRDB
import HiveKit

/// When each of a server's filesystems fills, at the rate its available space fell over the last week,
/// from its hourly figures.
struct FilesystemForecaster: Sendable {
    static let windowSeconds: Int64 = 7 * 86_400
    /// Fewer hours than this say too little about a rate to show one.
    static let fewestHours = 6
    /// Further off than this, a forecast says nothing useful.
    static let furthestSeconds: Int64 = 365 * 86_400

    let database: MetricsDatabase

    func forecasts(ofServer serverID: UUID) throws -> [FilesystemForecast] {
        try database.writer.read { database in
            let rows = try Row.fetchAll(database, sql: """
            SELECT metricsName.name, filesystemHour.startsAt, filesystemHour.available
            FROM filesystemHour
            JOIN metricsName ON metricsName.id = filesystemHour.nameID
            JOIN metricsServer ON metricsServer.id = metricsName.serverKey
            WHERE metricsServer.serverID = ? AND filesystemHour.available IS NOT NULL
                AND filesystemHour.startsAt > (
                    SELECT MAX(newest.startsAt) FROM filesystemHour AS newest WHERE newest.nameID = filesystemHour.nameID
                ) - ?
            ORDER BY metricsName.name, filesystemHour.startsAt
            """, arguments: [serverID, Self.windowSeconds])
            let byName = Dictionary(grouping: rows) { $0["name"] as String }
            return byName.keys.sorted().map { name in
                let hours = byName[name, default: []].map { (startsAt: $0["startsAt"] as Int64, available: $0["available"] as Double) }
                return Self.forecast(name, hours: hours)
            }
        }
    }

    /// `hours` oldest first, each at its start. The rate is the least-squares slope of available space,
    /// so a few unusual hours don't decide it, and it's projected from the newest hour.
    static func forecast(_ mountPoint: String, hours: [(startsAt: Int64, available: Double)]) -> FilesystemForecast {
        guard hours.count >= fewestHours, let newest = hours.last else {
            return FilesystemForecast(mountPoint: mountPoint, growthBytesPerDay: nil, fillsAt: nil)
        }
        let origin = Double(hours[0].startsAt)
        let times = hours.map { Double($0.startsAt) - origin }
        let count = Double(hours.count)
        let meanTime = times.reduce(0, +) / count
        let meanAvailable = hours.reduce(0) { $0 + $1.available } / count
        var covariance = 0.0
        var variance = 0.0
        for (time, hour) in zip(times, hours) {
            covariance += (time - meanTime) * (hour.available - meanAvailable)
            variance += (time - meanTime) * (time - meanTime)
        }
        let growthPerSecond = variance > 0 ? -covariance / variance : 0
        var fillsAt: Int64?
        if growthPerSecond > 0 {
            let seconds = newest.available / growthPerSecond
            if seconds <= Double(furthestSeconds) { fillsAt = newest.startsAt + Int64(seconds.rounded()) }
        }
        return FilesystemForecast(mountPoint: mountPoint, growthBytesPerDay: growthPerSecond * 86_400, fillsAt: fillsAt)
    }
}
