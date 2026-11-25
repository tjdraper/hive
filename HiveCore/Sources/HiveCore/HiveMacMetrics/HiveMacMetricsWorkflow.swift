import Foundation
import HiveKit
import os
import ScoutProtocol

/// Keeps a sample of the Hive Mac's own figures (§1), as a Scout's are kept, under the Hive's own ID,
/// with no enrollment, key or connection. It goes through the same checks, so the Mac's share of the
/// metrics database is limited as each server's is.
struct HiveMacMetricsWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Metrics")

    let hiveID: UUID
    let store: MetricsStore
    let board: MetricsLiveBoard
    let figureAlerts: FigureAlertCheck
    let drives: BackupDriveStore
    let driveMount: BackupDriveMountResolver
    let now: @Sendable () -> Date

    func keep(_ sample: MetricsSample) {
        let now = now()
        let report = MetricsReport(
            protocolVersion: ScoutProtocolVersion.current,
            sentAt: Int64(now.timeIntervalSince1970.rounded(.down)),
            samples: [sample],
            minutes: []
        )
        do {
            switch try store.keep(report, forServer: hiveID, at: now) {
            case .kept:
                if let latest = try ServerMetricsSummaryReader.latest(ofServer: hiveID, in: store.database) { board.post(latest) }
                checkAlerts(sample)
            case .refused(let reason):
                Self.logger.error("Refused the Hive Mac's figures: \(reason.rawValue, privacy: .public)")
            }
        } catch {
            Self.logger.error("Couldn't keep the Hive Mac's figures: \(String(describing: error), privacy: .public)")
        }
    }

    /// The backup drive has its own low-space email (§12), so its filesystems are left to it and not
    /// emailed about twice. Their space is still kept and charted with the rest.
    private func checkAlerts(_ sample: MetricsSample) {
        var checked = sample
        do {
            if let chosen = try drives.chosen(),
               let drive = driveMount.mountPoint(of: chosen.volumeUUID, among: sample.filesystems) {
                checked.filesystems = Self.leavingOutBackupDrive(sample.filesystems, mountPoint: drive)
            }
            let applied = try figureAlerts.check(checked, forServer: hiveID)
            for facts in applied.opened {
                Self.logger.notice("Opened an alert: \(facts.kind, privacy: .public)")
            }
            for facts in applied.ended {
                Self.logger.notice("Ended an alert: \(facts.kind, privacy: .public)")
            }
        } catch {
            Self.logger.error("Couldn't check the Hive Mac's figures for alerts: \(String(describing: error), privacy: .public)")
        }
    }

    /// Leaves out the drive's own volume, and the other APFS volumes in its container, which share its
    /// space, so they'd fill as it does.
    static func leavingOutBackupDrive(_ filesystems: [FilesystemFigures], mountPoint: String) -> [FilesystemFigures] {
        guard let drive = filesystems.first(where: { $0.mountPoint == mountPoint }) else { return filesystems }
        let container = apfsContainer(of: drive)
        return filesystems.filter { filesystem in
            filesystem.mountPoint != mountPoint && (container == nil || apfsContainer(of: filesystem) != container)
        }
    }

    /// The disk APFS makes for a container, whose slices are its volumes: `disk7` for `/dev/disk7s2`, and
    /// `disk3` for the startup disk's sealed snapshot, `/dev/disk3s1s1`.
    static func apfsContainer(of filesystem: FilesystemFigures) -> Substring? {
        guard filesystem.type == "apfs", let name = filesystem.device.split(separator: "/").last, name.hasPrefix("disk") else {
            return nil
        }
        let number = name.dropFirst("disk".count).prefix(while: \.isNumber)
        return number.isEmpty ? nil : name.prefix("disk".count + number.count)
    }
}
