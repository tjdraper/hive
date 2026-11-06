import Darwin
import Foundation
import HiveCore
import HiveKit
import os

enum DaemonStart {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "DaemonStartup")

    static func run(mode: DaemonLaunchMode) -> Never {
        let server: APIServer
        let pairing: LocalPairingListener
        do {
            let info = try DaemonInfo.read()
            let started = try DaemonStartupWorkflow(mode: mode).run()
            let keys = try HiveKeyStore(directory: started.dataDirectory).loadOrCreate()
            try HiveKeyCheck(directory: started.dataDirectory).run(keys)
            let certificate = try IdentityCertificateStore(directory: started.dataDirectory).loadOrIssue(for: keys.identity)
            let identity = TLSIdentity(key: keys.identity, certificate: certificate)

            let database = try HiveDatabase.open(in: started.dataDirectory)
            let hiveID = try database.hiveID()
            let devices = DeviceStore(database: database)
            let port = APIServer.defaultPort(for: mode)

            let signIn = SignInWorkflow(hiveID: hiveID, devices: devices, sessions: SessionStore())
            server = try APIServer(port: port, identity: identity, signIn: signIn)
            pairing = try LocalPairingListener(
                machService: info.pairingMachService,
                beekeeperSigningIdentifier: info.beekeeperSigningIdentifier,
                workflow: LocalPairingWorkflow(
                    hiveID: hiveID,
                    pin: PublicKeyPin(publicKey: keys.identity.publicKey),
                    port: port,
                    devices: devices
                )
            )
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
        withExtendedLifetime(pairing) {
            dispatchMain()
        }
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
