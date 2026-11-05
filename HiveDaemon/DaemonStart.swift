import Darwin
import Foundation
import HiveCore
import os

enum DaemonStart {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "DaemonStartup")

    static func run(mode: DaemonLaunchMode) -> Never {
        do {
            _ = try DaemonStartupWorkflow(mode: mode).run()
        } catch DaemonStartupError.nobodyLoggedIn {
            // launchd starts the daemon again shortly, until someone logs in.
            logger.notice("Nobody is logged in at the screen to record as Hive's user, exiting")
            exit(EX_TEMPFAIL)
        } catch {
            logger.fault("Startup failed: \(String(describing: error), privacy: .public)")
            exit(EX_CONFIG)
        }

        logger.notice("Startup finished")
        dispatchMain()
    }
}
