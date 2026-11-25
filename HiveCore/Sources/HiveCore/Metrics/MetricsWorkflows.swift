import Foundation
import HiveKit

/// The metrics workflows, built from the API's stores like the rest.
extension HiveAPI {
    var metricsReports: MetricsReportWorkflow {
        MetricsReportWorkflow(
            store: metrics, limiter: metricsLimiter, board: metricsBoard, naming: containerNaming, figureAlerts: figureAlerts,
            now: signIn.now
        )
    }

    var figureAlerts: FigureAlertCheck {
        let database = servers.store.database
        return FigureAlertCheck(
            hiveID: hiveID,
            alerts: AlertStore(database: database),
            metrics: metrics.database,
            limits: metricAlertLimits,
            now: signIn.now
        )
    }

    var metricAlertLimits: MetricAlertLimitsStore {
        MetricAlertLimitsStore(database: servers.store.database, now: signIn.now)
    }

    var containerNaming: ContainerNamingWorkflow {
        ContainerNamingWorkflow(database: metrics.database, targets: connectionTest.targets, ssh: connectionTest.ssh, now: signIn.now)
    }

    var metricsUpkeep: MetricsUpkeep {
        MetricsUpkeep(
            database: metrics.database,
            // The Hive Mac's figures are kept under the Hive's own ID, and kept while it's turned off.
            knownServerIDs: { [store = servers.store, hiveID] in Set(try store.all().map(\.id)).union([hiveID]) },
            now: signIn.now
        )
    }
}
