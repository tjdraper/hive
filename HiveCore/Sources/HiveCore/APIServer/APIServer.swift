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
        let service = ListeningService(
            listeners: listeners,
            factory: TLSListenerFactory(responder: Self.responder(api: api), tlsConfiguration: tlsConfiguration)
        )
        let group = ServiceGroup(configuration: ServiceGroupConfiguration(
            services: [service],
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
        OverviewRoutes.add(to: router, hiveID: api.hiveID, settings: api.settingsStore, fullDiskAccess: api.fullDiskAccess)
        DeviceRoutes.add(to: router, devices: api.devices, revocation: api.revocation)
        SettingsRoutes.add(to: router, workflow: api.settings)
        AuditLogRoutes.add(to: router, auditLog: api.auditLog)
        ServerRoutes.add(to: router, workflow: api.servers)
        BackupJobRoutes.add(to: router, workflow: api.jobs)
        SSHKeyRoutes.add(to: router, workflow: api.sshKeys)
        HostKeyRoutes.add(to: router, workflow: api.hostKeys)
        ConnectionTestRoutes.add(to: router, workflow: api.connectionTest)
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
