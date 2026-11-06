import Hummingbird
import HummingbirdTLS
import Logging
import NIOCore
import NIOSSL
import ServiceLifecycle
import Synchronization

enum TLSListenerError: Error {
    case stoppedBeforeListening
}

/// Hive's API on one address, over TLS. Each address gets its own server, since a Hummingbird server
/// binds one address, and they all share one responder.
final class TLSListener: APIListener {
    /// Closes a connection that sends nothing for this long, including one that never finishes its TLS handshake.
    static let idleTimeout = TimeAmount.seconds(30)

    /// Hummingbird and ServiceLifecycle log through swift-log, which would print addresses to standard
    /// output. Hive's own decisions are in the system log.
    static let quietLogger = Logging.Logger(label: "Hive", factory: { _ in SwiftLogNoOpLogHandler() })

    private final class StoppedFlag: Sendable {
        private let value = Mutex(false)

        var isSet: Bool {
            value.withLock { $0 }
        }

        func set() {
            value.withLock { $0 = true }
        }
    }

    private let group: ServiceGroup
    private let stopped: StoppedFlag
    private let finished: Task<Void, Never>

    var hasStopped: Bool {
        stopped.isSet
    }

    private init(group: ServiceGroup, finished: Task<Void, Never>, stopped: StoppedFlag) {
        self.group = group
        self.finished = finished
        self.stopped = stopped
    }

    static func start(
        on address: ListenerAddress,
        responder: some HTTPResponder<HiveRequestContext>,
        tlsConfiguration: TLSConfiguration
    ) async throws -> TLSListener {
        let (listening, listeningInput) = AsyncThrowingStream<Void, any Error>.makeStream()
        let application = Application(
            responder: responder,
            server: try .tls(.http1(configuration: .init(idleTimeout: idleTimeout)), tlsConfiguration: tlsConfiguration),
            configuration: ApplicationConfiguration(address: .hostname(address.host, port: address.port)),
            onServerRunning: { _ in listeningInput.yield() },
            logger: quietLogger
        )
        let group = ServiceGroup(configuration: ServiceGroupConfiguration(services: [application], logger: quietLogger))

        let stopped = StoppedFlag()
        let finished = Task {
            do {
                try await group.run()
                listeningInput.finish(throwing: TLSListenerError.stoppedBeforeListening)
            } catch {
                listeningInput.finish(throwing: error)
            }
            stopped.set()
        }

        var listeningEvents = listening.makeAsyncIterator()
        guard try await listeningEvents.next() != nil else { throw TLSListenerError.stoppedBeforeListening }
        return TLSListener(group: group, finished: finished, stopped: stopped)
    }

    func stop() async {
        await group.triggerGracefulShutdown()
    }

    func waitUntilStopped() async {
        await finished.value
    }
}

struct TLSListenerFactory<Responder: HTTPResponder<HiveRequestContext>>: APIListenerFactory {
    let responder: Responder
    let tlsConfiguration: TLSConfiguration

    func start(on address: ListenerAddress) async throws -> any APIListener {
        try await TLSListener.start(on: address, responder: responder, tlsConfiguration: tlsConfiguration)
    }
}
