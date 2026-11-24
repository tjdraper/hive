import Foundation
import HiveKit
import Hummingbird

/// A device's routes for reading servers' figures. A Scout's session never reaches them, since
/// `RequestGate` keeps it to its own routes.
enum MetricsReadingRoutes {
    static let seriesPath = RouterPath("\(HiveEndpoint.servers)/:id/metrics/series")
    static let processesPath = RouterPath("\(HiveEndpoint.servers)/:id/metrics/processes")
    static let forecastsPath = RouterPath("\(HiveEndpoint.servers)/:id/metrics/filesystem-forecasts")
    static let backupRunsPath = RouterPath("\(HiveEndpoint.servers)/:id/metrics/backup-runs")

    static func add(to router: Router<HiveRequestContext>, api: HiveAPI) {
        let (scouts, summaries, series, processes) = (api.scouts, api.metricsSummaries, api.metricsSeries, api.processMoments)
        let (forecasts, backupRuns) = (api.filesystemForecasts, api.backupRunMarks)

        router.get(RouterPath(HiveEndpoint.metricsSummary)) { _, _ in
            try JSONResponse(summaries.summaries())
        }

        router.get(seriesPath) { request, context in
            guard let id = try serverID(context, scouts: scouts) else { return JSONResponse(status: .notFound) }
            let parameters = request.uri.queryParameters
            let figures = parameters.get("figures")?.split(separator: ",").map { MetricsFigure(rawValue: String($0)) } ?? []
            guard let range = range(parameters), !figures.isEmpty, figures.allSatisfy({ $0 != nil }) else {
                return JSONResponse(status: .badRequest)
            }
            return try JSONResponse(series.series(ofServer: id, over: range, figures: figures.compactMap(\.self)))
        }

        router.get(processesPath) { request, context in
            guard let id = try serverID(context, scouts: scouts) else { return JSONResponse(status: .notFound) }
            guard let moment = request.uri.queryParameters.get("at", as: Int64.self) else { return JSONResponse(status: .badRequest) }
            return try JSONResponse(processes.processes(ofServer: id, at: moment))
        }

        router.get(forecastsPath) { _, context in
            guard let id = try serverID(context, scouts: scouts) else { return JSONResponse(status: .notFound) }
            return try JSONResponse(forecasts.forecasts(ofServer: id))
        }

        router.get(backupRunsPath) { request, context in
            guard let id = try serverID(context, scouts: scouts) else { return JSONResponse(status: .notFound) }
            guard let range = range(request.uri.queryParameters) else { return JSONResponse(status: .badRequest) }
            return try JSONResponse(backupRuns.marks(ofServer: id, over: range))
        }
    }

    /// Nil when there's no such server. One whose metrics were removed still has its history until it
    /// ages out.
    private static func serverID(_ context: HiveRequestContext, scouts: ScoutStore) throws -> UUID? {
        guard let id = context.idParameter, try scouts.hasMetrics(id) != nil else { return nil }
        return id
    }

    /// Nil unless `from` comes before `to` and they're no further apart than any chart shows.
    private static func range(_ parameters: Parameters) -> Range<Int64>? {
        guard let start = parameters.get("from", as: Int64.self), let end = parameters.get("to", as: Int64.self),
              start < end, end - start <= HiveEndpoint.longestMetricsRange
        else { return nil }
        return start ..< end
    }
}
