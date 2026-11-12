import os
import ServiceLifecycle

/// Restarts Hive once an update has replaced its executable. A run going now is cut short and picked up
/// after the restart, rather than holding back the new version for however long the run takes.
struct UpdateRestartService: Service {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Updates")

    let watcher: ExecutableReplacementWatcher
    let restart: HiveRestart

    func run() async throws {
        let isReplaced = await cancelWhenGracefulShutdown {
            await watcher.waitForReplacement()
        }
        guard isReplaced else { return }
        Self.logger.notice("Hive.app was replaced, restarting to run the new version")
        restart.request()
    }
}
