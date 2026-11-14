import Foundation
@testable import HiveKit
import Synchronization
import Testing

/// Which address `HiveConnection` sends a request to, and when it sends one again elsewhere.
struct ReachableAddressTests {
    private static let pin = PublicKeyPin(sha256: Data(repeating: 7, count: 32))
    private static let tailnet = HiveAddress(host: "studio.tail0000.ts.net", port: 4483)
    private static let lan = HiveAddress(host: "192.168.1.20", port: 4483)
    private static let local = HiveAddress(host: "Studio.local", port: 4483)

    private final class Probes: Sendable {
        private let asked = Mutex<[HiveAddress]>([])
        private let unreachable: Mutex<Set<HiveAddress>>

        init(unreachable: Set<HiveAddress> = []) {
            self.unreachable = Mutex(unreachable)
        }

        var all: [HiveAddress] {
            asked.withLock { $0 }
        }

        func setUnreachable(_ addresses: Set<HiveAddress>) {
            unreachable.withLock { $0 = addresses }
        }

        func probe(_ address: HiveAddress) async throws {
            asked.withLock { $0.append(address) }
            if unreachable.withLock({ $0.contains(address) }) { throw URLError(.timedOut) }
        }
    }

    @Test("A POST goes only to the address that answered, never to one that didn't")
    func postGoesOnlyWhereAnswered() async throws {
        // Arrange
        let connection = HiveConnection(addresses: [Self.lan, Self.tailnet], pin: Self.pin)
        let probes = Probes(unreachable: [Self.lan])
        var sent: [HiveAddress] = []

        // Act
        _ = try await connection.atReachableAddress(method: "POST", probe: probes.probe) { address -> Int in
            sent.append(address)
            return 1
        }

        // Assert
        #expect(sent == [Self.tailnet])
    }

    @Test("The address that answered is used next time without asking again")
    func remembersAddressThatAnswered() async throws {
        // Arrange
        let connection = HiveConnection(addresses: [Self.lan, Self.tailnet], pin: Self.pin)
        let probes = Probes(unreachable: [Self.lan])
        var sent: [HiveAddress] = []

        // Act
        for _ in 0 ..< 2 {
            _ = try await connection.atReachableAddress(method: "GET", probe: probes.probe) { address -> Int in
                sent.append(address)
                return 1
            }
        }

        // Assert
        #expect(sent == [Self.tailnet, Self.tailnet])
        #expect(probes.all.count == 2)
    }

    @Test("A POST that timed out isn't sent again, and the addresses are asked again next time")
    func timedOutPostNotResent() async throws {
        // Arrange
        let connection = HiveConnection(addresses: [Self.lan, Self.tailnet], pin: Self.pin)
        let probes = Probes(unreachable: [Self.tailnet])
        _ = try await connection.atReachableAddress(method: "GET", probe: probes.probe) { _ -> Int in 1 }
        probes.setUnreachable([Self.lan])
        var sent: [HiveAddress] = []

        // Act
        await #expect(throws: URLError(.timedOut)) {
            try await connection.atReachableAddress(method: "POST", probe: probes.probe) { address -> Int in
                sent.append(address)
                throw URLError(.timedOut)
            }
        }
        _ = try await connection.atReachableAddress(method: "POST", probe: probes.probe) { address -> Int in
            sent.append(address)
            return 1
        }

        // Assert
        #expect(sent == [Self.lan, Self.tailnet])
    }

    @Test("A GET the remembered address can't take is sent to the address that answers")
    func getMovesOn() async throws {
        // Arrange
        let connection = HiveConnection(addresses: [Self.lan, Self.tailnet], pin: Self.pin)
        let probes = Probes(unreachable: [Self.tailnet])
        _ = try await connection.atReachableAddress(method: "GET", probe: probes.probe) { _ -> Int in 1 }
        probes.setUnreachable([Self.lan])
        var sent: [HiveAddress] = []

        // Act
        _ = try await connection.atReachableAddress(method: "GET", probe: probes.probe) { address -> Int in
            sent.append(address)
            if address == Self.lan { throw URLError(.timedOut) }
            return 1
        }

        // Assert
        #expect(sent == [Self.lan, Self.tailnet])
    }

    @Test("A found address that's already one of the Hive's own is asked once")
    func duplicateAskedOnce() async {
        // Arrange
        let connection = HiveConnection(addresses: [Self.local], pin: Self.pin)
        connection.useDiscoveredAddresses([Self.local])
        let probes = Probes(unreachable: [Self.local])

        // Act
        _ = try? await connection.atReachableAddress(method: "GET", probe: probes.probe) { _ -> Int in 1 }

        // Assert
        #expect(probes.all == [Self.local])
    }
}
