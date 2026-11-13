import Darwin
import Foundation
import HiveCore
import HiveKit
import os
import SystemConfiguration

enum DaemonStart {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "DaemonStartup")

    static func run(mode: DaemonLaunchMode) -> Never {
        let server: APIServer
        let pairing: LocalPairingListener
        do {
            let info = try DaemonInfo.read()
            let started = try DaemonStartupWorkflow(mode: mode).run()
            let keyStore = HiveKeyStore(directory: started.dataDirectory)
            let keys = try keyStore.loadOrCreate()
            let identity = try checkedIdentity(for: keys, in: started.dataDirectory)

            let database = try HiveDatabase.open(in: started.dataDirectory, defaultHiveName: defaultHiveName())
            let hiveID = try database.hiveID()
            let settings = HiveSettingsStore(database: database, defaultPort: APIServer.defaultPort(for: mode))
            let listeners = ListenerCoordinator(target: try settings.settings().listenTarget(hiveID: hiveID))
            let pin = PublicKeyPin(publicKey: keys.identity.publicKey)

            let api = HiveAPI(
                hiveID: hiveID,
                pin: pin,
                database: database,
                dataDirectory: started.dataDirectory,
                settings: settings,
                listeners: listeners,
                sealer: SecretSealer(key: keys.storage),
                identityKeys: keyStore,
                rsync: bundledRsync(),
                version: info.version,
                executable: executable
            )
            server = try APIServer(api: api, identity: identity, listeners: listeners)
            pairing = try LocalPairingListener(
                machService: info.pairingMachService,
                beekeeperSigningIdentifier: info.beekeeperSigningIdentifier,
                workflow: LocalPairingWorkflow(
                    hiveID: hiveID,
                    pin: pin,
                    settings: settings,
                    devices: DeviceStore(database: database),
                    isRestarting: { api.isRestarting }
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

    private static var executable: URL {
        Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0])
    }

    /// Checks the keys work before anything relies on them (§7), and makes the TLS identity from them.
    private static func checkedIdentity(for keys: HiveKeys, in dataDirectory: URL) throws -> TLSIdentity {
        try HiveKeyCheck(directory: dataDirectory).run(keys)
        let certificate = try IdentityCertificateStore(directory: dataDirectory).loadOrIssue(for: keys.identity)
        return TLSIdentity(key: keys.identity, certificate: certificate)
    }

    /// Hive still starts without it, so Beekeeper can show the runs failing rather than a Hive that's offline.
    private static func bundledRsync() -> URL {
        let rsync = BundledRsync.url(besideExecutable: executable)
        if !BundledRsync.isPresent(at: rsync) {
            logger.fault("The bundled rsync is missing from Hive.app, so every backup will fail")
        }
        return rsync
    }

    /// The Mac's name, as set in System Settings › General › Sharing, so a new Hive is named for its Mac.
    private static func defaultHiveName() -> String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Hive"
    }

    /// Runs until launchd sends SIGTERM. A server that can't start, such as when its port is taken, ends
    /// the daemon so launchd starts it again.
    private static func serve(_ server: APIServer) {
        Task {
            do {
                try await server.run()
                // launchd's KeepAlive starts it again, which is how a restart Hive asks for takes effect.
                logger.notice("The API server stopped")
                exit(EXIT_SUCCESS)
            } catch {
                logger.fault("The API server failed: \(String(describing: error), privacy: .public)")
                exit(EX_UNAVAILABLE)
            }
        }
    }
}
