import Foundation
import HiveKit

/// The metrics workflows, built from the API's stores like the rest.
extension HiveAPI {
    var metricsReports: MetricsReportWorkflow {
        MetricsReportWorkflow(store: metrics, limiter: metricsLimiter, now: signIn.now)
    }

    var metricsUpkeep: MetricsUpkeep {
        MetricsUpkeep(
            database: metrics.database,
            knownServerIDs: { [store = servers.store] in Set(try store.all().map(\.id)) },
            now: signIn.now
        )
    }
}
