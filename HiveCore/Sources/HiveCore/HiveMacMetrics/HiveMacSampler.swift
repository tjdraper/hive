import Foundation
import GRDB
import HiveKit
import ScoutCore

/// Samples the Hive Mac with Scout's macOS readers, on the same 10-second marks as every Scout (§5),
/// while the setting is on. While Hive isn't running nothing samples, so its downtime is a gap.
struct HiveMacSampler: Sendable {
    let workflow: HiveMacMetricsWorkflow
    let settings: HiveSettingsStore

    func run() async {
        var sampler: MacSampler?
        while !Task.isCancelled {
            let mark = SampleSchedule.nextMark(after: SampleSchedule.now())
            do {
                try await Task.sleep(for: .nanoseconds(mark - SampleSchedule.now()))
            } catch {
                return
            }
            await step(at: mark / 1_000_000_000, sampler: &sampler)
        }
    }

    /// Takes and keeps the sample due at `mark`, in seconds since 1970, while the setting is on. Its
    /// sampler is dropped while it's off, so no rate spans the time it was.
    func step(at mark: Int64, sampler: inout MacSampler?) async {
        guard (try? settings.settings().collectsMacMetrics) == true else {
            sampler = nil
            return
        }
        var current = sampler ?? MacSampler()
        let sample = await current.sample(takenAt: mark)
        sampler = current
        workflow.keep(sample)
    }
}

extension HiveAPI {
    var hiveMacSampler: HiveMacSampler {
        HiveMacSampler(
            workflow: HiveMacMetricsWorkflow(
                hiveID: hiveID,
                store: metrics,
                board: metricsBoard,
                figureAlerts: figureAlerts,
                drives: backupDrive.store,
                volumes: backupDrive.volumes,
                now: signIn.now
            ),
            settings: settingsStore
        )
    }
}

/// The store's migration for the Hive Mac's metrics, registered in order with the rest in `HiveDatabaseMigrator`.
extension HiveDatabaseMigrator {
    static func addHiveMacMetrics(_ database: Database) throws {
        try database.alter(table: "hive") { table in
            table.add(column: "collectsMacMetrics", .boolean).notNull().defaults(to: true)
            // When the Mac last started, as its newest sample said, so a restart is emailed about once,
            // as `scout.bootedAt` is for a server.
            table.add(column: "macBootedAt", .integer)
        }
    }
}

/// The Hive Mac's figures are kept under the Hive's own ID, as a server's are under its ID.
enum HiveMac {
    /// The Hive's ID while it reads its Mac's figures, and nil while that's turned off.
    static func collectingID(in database: HiveDatabase) throws -> UUID? {
        try database.writer.read { try UUID.fetchOne($0, sql: "SELECT id FROM hive WHERE collectsMacMetrics") }
    }

    /// Whether `id` is the Hive's own, which has figures kept until they age out, even while it's
    /// turned off.
    static func isHive(_ id: UUID, in database: HiveDatabase) throws -> Bool {
        try database.writer.read { try UUID.fetchOne($0, sql: "SELECT id FROM hive") } == id
    }
}
