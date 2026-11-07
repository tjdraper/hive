import Foundation
import HiveKit
import os

/// Gives the backup drive a few minutes to mount after Hive starts (§4), so a drive that mounts late
/// doesn't fail every job that was due while Hive was off.
struct StartupDriveWait: Sendable {
    static let checkInterval: Duration = .seconds(10)

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Backup")

    let drives: BackupDriveLocator
    /// Runs this long after `hiveStartedAt` wait for the drive. Later ones fail at once without it.
    let grace: TimeInterval
    let hiveStartedAt: Date
    let pause: @Sendable (Duration) async throws -> Void
    let now: @Sendable () -> Date

    /// Returns once the drive is mounted, or Hive has been running for `grace`. `waiting` is called
    /// once, if it has to wait.
    func untilMounted(waiting: () async -> Void) async throws {
        var announced = false
        while now() < hiveStartedAt.addingTimeInterval(grace), case .unavailable(.driveMissing)? = try? drives.locate() {
            if !announced {
                Self.logger.notice("Waiting for the backup drive to mount")
                await waiting()
                announced = true
            }
            try await pause(Self.checkInterval)
        }
    }
}
