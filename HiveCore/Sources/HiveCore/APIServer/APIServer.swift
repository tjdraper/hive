import Foundation
import HiveKit
import Hummingbird
import HummingbirdTLS
import NIOCore
import os

/// Hive's HTTPS API. It listens on `127.0.0.1` only, for Beekeeper on the Hive Mac.
public struct APIServer: Sendable {
    /// Closes a connection that sends nothing for this long, including one that never finishes its TLS handshake.
    static let idleTimeout = TimeAmount.seconds(30)

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "APIServer")

    private let application: any ApplicationProtocol

    public init(port: Int, identity: TLSIdentity, signIn: SignInWorkflow) throws {
        application = Application(
            responder: Self.responder(signIn: signIn),
            server: try .tls(
                .http1(configuration: .init(idleTimeout: Self.idleTimeout)),
                tlsConfiguration: try identity.serverConfiguration()
            ),
            configuration: ApplicationConfiguration(address: .hostname("127.0.0.1", port: port)),
            onServerRunning: { _ in
                Self.logger.notice("Serving the API over TLS on 127.0.0.1, port \(port, privacy: .public)")
            }
        )
    }

    /// 4483 isn't assigned to anything. The development agent takes the next port, so it can run beside an installed Hive.
    public static func defaultPort(for mode: DaemonLaunchMode) -> Int {
        switch mode {
        case .systemDaemon: 4483
        case .developmentAgent: 4484
        }
    }

    /// Runs until the process is sent SIGTERM or SIGINT.
    public func run() async throws {
        try await application.runService()
    }

    static func router(signIn: SignInWorkflow) -> Router<HiveRequestContext> {
        let router = Router(context: HiveRequestContext.self)
        router.get(RouterPath(HiveEndpoint.health)) { _, _ in
            HTTPResponse.Status.noContent
        }
        SignInRoutes.add(to: router, workflow: signIn)
        return router
    }

    static func responder(signIn: SignInWorkflow) -> some HTTPResponder<HiveRequestContext> {
        RequestGate(next: router(signIn: signIn).buildResponder(), sessions: signIn.sessions, now: signIn.now)
    }
}
