import Foundation
@testable import HiveCore
import HiveKit
import Synchronization
import Testing

/// Starts fake listeners, and refuses the addresses it's told to as if they were taken.
final class FakeListenerFactory: APIListenerFactory {
    final class Listener: APIListener {
        let address: ListenerAddress
        private let stopped = Mutex(false)

        init(address: ListenerAddress) {
            self.address = address
        }

        var hasStopped: Bool {
            stopped.withLock { $0 }
        }

        func stop() async {
            stopped.withLock { $0 = true }
        }

        func waitUntilStopped() async {
            // Stopping a fake is immediate.
        }
    }

    private struct State {
        var refused: Set<ListenerAddress> = []
        var started: [Listener] = []
    }

    private let state = Mutex(State())

    var started: [Listener] {
        state.withLock { $0.started }
    }

    var running: Set<ListenerAddress> {
        Set(started.filter { !$0.hasStopped }.map(\.address))
    }

    func refuse(_ address: ListenerAddress) {
        state.withLock { _ = $0.refused.insert(address) }
    }

    func start(on address: ListenerAddress) async throws -> any APIListener {
        try state.withLock { state in
            if state.refused.contains(address) { throw FakeListenerError.addressInUse }
            let listener = Listener(address: address)
            state.started.append(listener)
            return listener
        }
    }
}

enum FakeListenerError: Error {
    case addressInUse
}

/// Keeps what it was last told to advertise.
final class FakeAdvertiser: LocalNetworkAdvertiser {
    private let latest = Mutex<LocalNetworkAdvertisement?>(nil)

    var advertised: LocalNetworkAdvertisement? {
        latest.withLock { $0 }
    }

    func advertise(_ advertisement: LocalNetworkAdvertisement?) {
        latest.withLock { $0 = advertisement }
    }
}

final class FakeAddresses: Sendable {
    private let present = Mutex<Set<String>>([])

    var current: Set<String> {
        present.withLock { $0 }
    }

    func set(_ addresses: Set<String>) {
        present.withLock { $0 = addresses }
    }
}

struct ListenerCoordinatorTests {
    private static let tailscale = "100.106.46.52"

    private let factory = FakeListenerFactory()
    private let addresses = FakeAddresses()
    private let advertiser = FakeAdvertiser()

    private func coordinator(_ access: NetworkAccess, port: Int = 4483) -> ListenerCoordinator {
        ListenerCoordinator(
            target: ListenTarget(networkAccess: access, port: port),
            presentAddresses: { [addresses] in addresses.current },
            localNetworks: { [] },
            advertiser: advertiser
        )
    }

    private func address(_ host: String, port: Int = 4483) -> ListenerAddress {
        ListenerAddress(host: host, port: port)
    }

    @Test("An address that appears after Hive starts is listened on at the next check")
    func picksUpAddressThatAppears() async throws {
        // Arrange
        let target = ListenTarget(networkAccess: .address(Self.tailscale), port: 4483)
        let coordinator = coordinator(target.networkAccess)
        try await coordinator.reconcile(to: target, using: factory)
        #expect(factory.running == [address("127.0.0.1")])

        // Act
        addresses.set([Self.tailscale])
        try await coordinator.reconcile(to: target, using: factory)

        // Assert
        #expect(factory.running == [address("127.0.0.1"), address(Self.tailscale)])
    }

    @Test("An address that goes away stops being listened on, and comes back when it does")
    func followsAddressAwayAndBack() async throws {
        // Arrange
        addresses.set([Self.tailscale])
        let target = ListenTarget(networkAccess: .address(Self.tailscale), port: 4483)
        let coordinator = coordinator(target.networkAccess)
        try await coordinator.reconcile(to: target, using: factory)

        // Act
        addresses.set([])
        try await coordinator.reconcile(to: target, using: factory)
        let whileAway = factory.running
        addresses.set([Self.tailscale])
        try await coordinator.reconcile(to: target, using: factory)

        // Assert
        #expect(whileAway == [address("127.0.0.1")])
        #expect(factory.running == [address("127.0.0.1"), address(Self.tailscale)])
    }

    @Test("Going back to this Mac only stops every other listener and keeps 127.0.0.1's")
    func narrowsToThisMac() async throws {
        // Arrange
        let coordinator = coordinator(.allAddresses)
        try await coordinator.reconcile(to: ListenTarget(networkAccess: .allAddresses, port: 4483), using: factory)
        let started = factory.started.first(where: \.address.isLoopback)
        let loopback = try #require(started)

        // Act
        try await coordinator.reconcile(to: ListenTarget(networkAccess: .thisMacOnly, port: 4483), using: factory)

        // Assert
        #expect(factory.running == [address("127.0.0.1")])
        #expect(!loopback.hasStopped)
        #expect(await coordinator.listeningHosts() == ["127.0.0.1"])
    }

    @Test("A new port that's taken on 127.0.0.1 is refused, and Hive keeps listening as before")
    func takenPortChangesNothing() async throws {
        // Arrange
        addresses.set([Self.tailscale])
        let coordinator = coordinator(.address(Self.tailscale))
        try await coordinator.reconcile(to: ListenTarget(networkAccess: .address(Self.tailscale), port: 4483), using: factory)
        factory.refuse(address("127.0.0.1", port: 5000))

        // Act
        await #expect(throws: ListenerCoordinatorError.loopbackUnavailable) {
            try await coordinator.reconcile(to: ListenTarget(networkAccess: .allAddresses, port: 5000), using: factory)
        }

        // Assert
        #expect(factory.running == [address("127.0.0.1"), address(Self.tailscale)])
        #expect(Set(await coordinator.listeningHosts()) == ["127.0.0.1", Self.tailscale])
    }

    @Test("Changing the port starts the new listeners before stopping the old ones")
    func changesPort() async throws {
        // Arrange
        let coordinator = coordinator(.thisMacOnly)
        try await coordinator.reconcile(to: ListenTarget(networkAccess: .thisMacOnly, port: 4483), using: factory)

        // Act
        try await coordinator.reconcile(to: ListenTarget(networkAccess: .thisMacOnly, port: 5000), using: factory)

        // Assert
        #expect(factory.running == [address("127.0.0.1", port: 5000)])
        #expect(factory.started.map(\.address) == [address("127.0.0.1"), address("127.0.0.1", port: 5000)])
    }

    @Test("A chosen address that can't be bound doesn't stop 127.0.0.1, and is tried again later")
    func retriesChosenAddress() async throws {
        // Arrange
        addresses.set([Self.tailscale])
        let target = ListenTarget(networkAccess: .address(Self.tailscale), port: 4483)
        let coordinator = coordinator(target.networkAccess)
        factory.refuse(address(Self.tailscale))

        // Act
        try await coordinator.reconcile(to: target, using: factory)

        // Assert
        #expect(factory.running == [address("127.0.0.1")])
    }

    @Test("A listener that stopped on its own is started again")
    func restartsStoppedListener() async throws {
        // Arrange
        let target = ListenTarget(networkAccess: .thisMacOnly, port: 4483)
        let coordinator = coordinator(target.networkAccess)
        try await coordinator.reconcile(to: target, using: factory)
        await factory.started[0].stop()

        // Act
        try await coordinator.reconcile(to: target, using: factory)

        // Assert
        #expect(factory.started.count == 2)
        #expect(factory.running == [address("127.0.0.1")])
    }
}

struct ListenerCoordinatorRunTests {
    @Test("While running, changes are applied in turn, and stopping stops every listener")
    func appliesWhileRunningAndStops() async throws {
        // Arrange
        let factory = FakeListenerFactory()
        let advertiser = FakeAdvertiser()
        let wiFi = LocalNetworkInterface(name: "en0", index: 4, addresses: ["192.168.1.20"])
        let hive = AdvertisedHive(hiveID: UUID(), name: "Studio Hive")
        let coordinator = ListenerCoordinator(
            target: ListenTarget(networkAccess: .thisMacOnly, port: 4483, advertised: hive),
            presentAddresses: { [] },
            localNetworks: { [wiFi] },
            advertiser: advertiser
        )
        let running = Task { try await coordinator.run(with: factory) }

        // Act
        try await coordinator.apply(ListenTarget(networkAccess: .allAddresses, port: 4483, advertised: hive))
        let whileRunning = factory.running
        let advertisedWhileRunning = advertiser.advertised
        running.cancel()
        try await running.value

        // Assert
        #expect(whileRunning == [ListenerAddress(host: "127.0.0.1", port: 4483), ListenerAddress(host: "::", port: 4483)])
        #expect(advertisedWhileRunning == LocalNetworkAdvertisement(hive: hive, port: 4483, interfaces: [4]))
        #expect(factory.running.isEmpty)
        #expect(advertiser.advertised == nil)
    }
}
