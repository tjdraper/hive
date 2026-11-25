import Foundation

/// The readers of servers' figures, built from the API's stores like the rest.
extension HiveAPI {
    var metricsSummaries: ServerMetricsSummaryReader {
        ServerMetricsSummaryReader(scouts: scouts, database: metrics.database, now: signIn.now)
    }

    var metricsSeries: MetricsSeriesReader {
        MetricsSeriesReader(database: metrics.database, now: signIn.now)
    }

    var processMoments: ProcessMomentReader {
        ProcessMomentReader(database: metrics.database)
    }

    var cgroupMoments: CgroupMomentReader {
        CgroupMomentReader(database: metrics.database)
    }

    var cgroupSeries: CgroupSeriesReader {
        CgroupSeriesReader(database: metrics.database, now: signIn.now)
    }

    var filesystemForecasts: FilesystemForecaster {
        FilesystemForecaster(database: metrics.database)
    }

    var backupRunMarks: BackupRunMarkReader {
        BackupRunMarkReader(jobLog: jobLog, metrics: metrics)
    }
}
