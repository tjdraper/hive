import Foundation
import HiveKit
import os
import ServiceLifecycle

/// One address Hive is listening on.
protocol APIListener: Sendable {
    /// True once it has stopped for any reason, including failing after it started.
    var hasStopped: Bool { get }
    /// Stops taking connections. Requests already under way finish first, including the one that
    /// changed the settings, so this never waits for them.
    func stop() async
    func waitUntilStopped() async
}

protocol APIListenerFactory: Sendable {
    /// Returns once it's listening, or throws when the address can't be bound.
    func start(on address: ListenerAddress) async throws -> any APIListener
}

public enum ListenerCoordinatorError: Error, Equatable {
    /// Something else holds the port on `127.0.0.1`.
    case loopbackUnavailable
    case shuttingDown
}

/// Keeps Hive listening on the addresses its settings ask for: on start, when the settings change, and
/// when an address appears or goes away, such as Tailscale's after login.
public actor ListenerCoordinator: ListenerControl {
    /// Polling is simpler than subscribing to SystemConfiguration's change notifications, and an address
    /// that appears is picked up soon enough.
    static let recheckInterval = Duration.seconds(5)

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Listening")

    private enum Command {
        case recheck
        case apply(ListenTarget, CheckedContinuation<Void, any Error>)
    }

    private var target: ListenTarget
    private var listeners: [ListenerAddress: any APIListener] = [:]
    /// Addresses whose last attempt failed, so a failure that repeats every recheck is logged once.
    private var failing: Set<ListenerAddress> = []
    private let presentAddresses: @Sendable () -> Set<String>
    private let commands: AsyncStream<Command>
    private let commandInput: AsyncStream<Command>.Continuation

    public init(target: ListenTarget) {
        self.init(target: target, presentAddresses: NetworkInterfaceList.presentAddresses)
    }

    init(target: ListenTarget, presentAddresses: @escaping @Sendable () -> Set<String>) {
        self.target = target
        self.presentAddresses = presentAddresses
        (commands, commandInput) = AsyncStream.makeStream()
    }

    /// Listens until graceful shutdown or cancellation, then stops every listener and waits for them.
    /// Throws at once when it can't listen on `127.0.0.1`.
    func run(with factory: any APIListenerFactory) async throws {
        try await reconcile(to: target, using: factory)
        Self.logger.notice("Listening, \(Self.describe(self.target.networkAccess), privacy: .public)")

        let ticker = Task { [commandInput] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.recheckInterval)
                commandInput.yield(.recheck)
            }
        }
        await withGracefulShutdownHandler {
            for await command in commands {
                await handle(command, using: factory)
            }
        } onGracefulShutdown: { [commandInput] in
            commandInput.finish()
        }
        ticker.cancel()
        await stopAll()
    }

    /// Changes take effect in the order they arrive, one at a time. Throws, changing nothing, when the
    /// new port is taken on `127.0.0.1`.
    func apply(_ target: ListenTarget) async throws {
        try await withCheckedThrowingContinuation { continuation in
            if case .terminated = commandInput.yield(.apply(target, continuation)) {
                continuation.resume(throwing: ListenerCoordinatorError.shuttingDown)
            }
        }
    }

    func listeningHosts() -> [String] {
        listeners.filter { !$0.value.hasStopped }.keys.map(\.host).sorted()
    }

    private func handle(_ command: Command, using factory: any APIListenerFactory) async {
        switch command {
        case .recheck:
            do {
                try await reconcile(to: target, using: factory)
            } catch {
                Self.logger.fault("Stopped listening on 127.0.0.1 and couldn't start again")
            }
        case .apply(let newTarget, let continuation):
            do {
                try await reconcile(to: newTarget, using: factory)
                target = newTarget
                Self.logger.notice("Listening, \(Self.describe(newTarget.networkAccess), privacy: .public)")
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Starts what's missing before stopping what's no longer wanted, so a change that fails leaves
    /// Hive listening as before. Only `127.0.0.1` is required. Another address that can't be bound is
    /// tried again at the next recheck.
    func reconcile(to target: ListenTarget, using factory: any APIListenerFactory) async throws {
        listeners = listeners.filter { !$0.value.hasStopped }
        let wanted = ListenPlan.addresses(for: target, present: presentAddresses())

        var started: [ListenerAddress: any APIListener] = [:]
        for address in wanted.subtracting(listeners.keys).sorted(by: { $0.isLoopback && !$1.isLoopback }) {
            do {
                started[address] = try await factory.start(on: address)
                failing.remove(address)
            } catch where address.isLoopback {
                for listener in started.values { await listener.stop() }
                Self.logger.error("Couldn't listen on 127.0.0.1: \(String(describing: error), privacy: .public)")
                throw ListenerCoordinatorError.loopbackUnavailable
            } catch {
                if failing.insert(address).inserted {
                    Self.logger.error("Couldn't listen on a chosen address: \(String(describing: error), privacy: .public)")
                }
            }
        }

        for (address, listener) in listeners where !wanted.contains(address) {
            await listener.stop()
            listeners[address] = nil
        }
        listeners.merge(started) { _, new in new }
        failing.formIntersection(wanted)
    }

    private func stopAll() async {
        for listener in listeners.values { await listener.stop() }
        for listener in listeners.values { await listener.waitUntilStopped() }
        listeners = [:]
        Self.logger.notice("Stopped listening")
    }

    private static func describe(_ access: HiveKit.NetworkAccess) -> String {
        switch access {
        case .thisMacOnly: "on this Mac only"
        case .address: "on this Mac and one chosen address"
        case .allAddresses: "on all addresses"
        }
    }
}
