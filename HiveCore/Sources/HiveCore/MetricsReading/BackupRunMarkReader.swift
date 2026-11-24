import Foundation
import GRDB
import HiveKit

/// A server's backup runs in a range of its figures, for marking on its charts. The job log keeps
/// Hive's clock and figures the server's, so each run is moved by the server's last known offset.
struct BackupRunMarkReader: Sendable {
    let jobLog: JobLog
    let metrics: MetricsStore

    /// `range` is seconds since 1970 on the server's clock.
    func marks(ofServer serverID: UUID, over range: Range<Int64>) throws -> [BackupRunMark] {
        let offset = try metrics.server(serverID)?.clockOffsetSeconds ?? 0
        let hiveDate = { (seconds: Int64) in Date(timeIntervalSince1970: TimeInterval(seconds - offset)) }
        let serverTime = { (date: Date) in Int64(date.timeIntervalSince1970.rounded(.down)) + offset }
        return try jobLog.runs(ofServer: serverID, from: hiveDate(range.lowerBound), to: hiveDate(range.upperBound)).map { entry in
            BackupRunMark(
                jobID: entry.run.jobID,
                jobName: entry.jobName,
                startedAt: serverTime(entry.run.startedAt),
                finishedAt: entry.run.finishedAt.map(serverTime),
                failure: entry.run.failure
            )
        }
    }
}
