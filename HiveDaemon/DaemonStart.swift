import Darwin
import Foundation
import HiveCore
import os

enum DaemonStart {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "DaemonStartup")

    static func run(mode: DaemonLaunchMode) -> Never {
        let server: APIServer
        do {
            let started = try DaemonStartupWorkflow(mode: mode).run()
            let keys = try HiveKeyStore(directory: started.dataDirectory).loadOrCreate()
            try HiveKeyCheck(directory: started.dataDirectory).run(keys)
            let certificate = try IdentityCertificateStore(directory: started.dataDirectory).loadOrIssue(for: keys.identity)
            let identity = TLSIdentity(key: keys.identity, certificate: certificate)
            server = try APIServer(port: APIServer.defaultPort(for: mode), identity: identity)
        } catch DaemonStartupError.nobodyLoggedIn {
            // launchd starts the daemon again shortly, until someone logs in.
            logger.notice("Nobody is logged in at the screen to record as Hive's user, exiting")
            exit(EX_TEMPFAIL)
        } catch {
            logger.fault("Startup failed: \(String(describing: error), privacy: .public)")
            exit(EX_CONFIG)
        }

        logger.notice("Startup finished")
        serve(server)
        dispatchMain()
    }

    /// Runs until launchd sends SIGTERM. A server that can't start, such as when its port is taken, ends
    /// the daemon so launchd starts it again.
    private static func serve(_ server: APIServer) {
        Task {
            do {
                try await server.run()
                logger.notice("The API server stopped")
                exit(EXIT_SUCCESS)
            } catch {
                logger.fault("The API server failed: \(String(describing: error), privacy: .public)")
                exit(EX_UNAVAILABLE)
            }
        }
    }
}
