import Foundation
import HiveKit
import Hummingbird
import NIOSSL
import ServiceLifecycle
import UnixSignals

/// Hive's HTTPS API, on `127.0.0.1` and wherever else the settings say.
public struct APIServer: Sendable {
    private let api: HiveAPI
    private let listeners: ListenerCoordinator
    private let tlsConfiguration: TLSConfiguration

    public init(api: HiveAPI, identity: TLSIdentity, listeners: ListenerCoordinator) throws {
        self.api = api
        self.listeners = listeners
        tlsConfiguration = try identity.serverConfiguration()
    }

    /// 4483 isn't assigned to anything. The development agent takes the next port, so it can run beside an installed Hive.
    public static func defaultPort(for mode: DaemonLaunchMode) -> Int {
        switch mode {
        case .systemDaemon: 4483
        case .developmentAgent: 4484
        }
    }

    /// Runs until the process is sent SIGTERM or SIGINT. Throws when it can't listen on `127.0.0.1`.
    public func run() async throws {
        // Before anything can reach the queue, so a run a restart cut short can't be taken for one going now.
        try await api.runs.start()
        let service = ListeningService(
            listeners: listeners,
            factory: TLSListenerFactory(responder: Self.responder(api: api), tlsConfiguration: tlsConfiguration)
        )
        let group = ServiceGroup(configuration: ServiceGroupConfiguration(
            services: [
                .init(service: service),
                .init(service: SchedulingService(scheduler: api.scheduler, runs: api.runs)),
                .init(service: AlertService(monitor: api.alerts)),
                .init(service: RecoveryFileService(writer: api.recoveryFiles)),
                .init(service: RestartService(restart: api.restart), successTerminationBehavior: .gracefullyShutdownGroup),
            ],
            gracefulShutdownSignals: [.sigterm, .sigint],
            logger: TLSListener.quietLogger
        ))
        try await group.run()
    }

    static func router(api: HiveAPI) -> Router<HiveRequestContext> {
        let router = Router(context: HiveRequestContext.self)
        router.get(RouterPath(HiveEndpoint.health)) { _, _ in
            HTTPResponse.Status.noContent
        }
        SignInRoutes.add(to: router, workflow: api.signIn)
        OverviewRoutes.add(
            to: router,
            hiveID: api.hiveID,
            settings: api.settingsStore,
            fullDiskAccess: api.fullDiskAccess,
            macSleep: api.macSleep
        )
        DeviceRoutes.add(to: router, devices: api.devices, revocation: api.revocation)
        ConfirmationRoutes.add(to: router, verifier: api.confirmations)
        IdentityRoutes.add(to: router, workflow: api.identity, confirmations: api.confirmations)
        SettingsRoutes.add(to: router, workflow: api.settings)
        EmailRoutes.add(to: router, workflow: api.email, confirmations: api.confirmations)
        RecoveryKeyRoutes.add(to: router, workflow: api.recoveryKey, confirmations: api.confirmations)
        AuditLogRoutes.add(to: router, auditLog: api.auditLog)
        ServerRoutes.add(to: router, workflow: api.servers, confirmations: api.confirmations)
        ServerSpaceRoutes.add(to: router, reader: api.serverSpace)
        RemovalEstimateRoutes.add(to: router, estimator: api.removalEstimator)
        BackupJobRoutes.add(to: router, workflow: api.jobs, confirmations: api.confirmations)
        SSHKeyRoutes.add(to: router, workflow: api.sshKeys, confirmations: api.confirmations)
        HostKeyRoutes.add(to: router, workflow: api.hostKeys, confirmations: api.confirmations)
        ConnectionTestRoutes.add(to: router, workflow: api.connectionTest)
        BackupDriveRoutes.add(to: router, workflow: api.backupDrive)
        BackupRunRoutes.add(to: router, coordinator: api.runs, statuses: api.jobStatus)
        JobLogRoutes.add(to: router, jobLog: api.jobLog)
        SnapshotRoutes.add(to: router, reader: api.snapshots, removedJobs: api.removedJobs)
        SnapshotDeletionRoutes.add(to: router, store: api.snapshotDeletions, runs: api.runs, confirmations: api.confirmations)
        LiveUpdateRoutes.add(
            to: router,
            stream: LiveUpdateStream(
                events: api.runs.events,
                statuses: api.jobStatus,
                recovery: api.recoveryKey,
                heartbeat: api.liveUpdateHeartbeat
            ),
            signIn: api.signIn
        )
        return router
    }

    static func responder(api: HiveAPI) -> some HTTPResponder<HiveRequestContext> {
        RequestGate(next: router(api: api).buildResponder(), sessions: api.signIn.sessions, now: api.signIn.now)
    }
}

private struct ListeningService: Service {
    let listeners: ListenerCoordinator
    let factory: any APIListenerFactory

    func run() async throws {
        try await listeners.run(with: factory)
    }
}

/// Returns once a restart is asked for, which shuts the rest down gracefully, or when Hive is stopping anyway.
private struct RestartService: Service {
    let restart: HiveRestart

    func run() async throws {
        await cancelWhenGracefulShutdown {
            await restart.wait()
        }
    }
}

private struct AlertService: Service {
    let monitor: AlertMonitor

    func run() async throws {
        await cancelWhenGracefulShutdown {
            await monitor.run()
        }
    }
}

private struct RecoveryFileService: Service {
    let writer: RecoveryFileWriter

    func run() async throws {
        await cancelWhenGracefulShutdown {
            await writer.run()
        }
    }
}

private struct SchedulingService: Service {
    let scheduler: BackupScheduler
    let runs: BackupRunCoordinator

    /// Stops the run going now before Hive exits, so its processes have their chance to clean up.
    func run() async throws {
        await cancelWhenGracefulShutdown {
            await scheduler.run()
        }
        await runs.stop()
    }
}
