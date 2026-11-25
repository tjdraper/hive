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
            knownServerIDs: { [store = servers.store] in Set(try store.all().map(\.id)) },
            now: signIn.now
        )
    }
}
