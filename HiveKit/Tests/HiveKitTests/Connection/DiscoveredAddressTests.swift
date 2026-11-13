import Foundation
@testable import HiveKit
import Testing

/// Anything on the local network can advertise any Hive, so another key shown at an address found
/// there never reads as the Hive's identity having changed.
struct DiscoveredAddressTests {
    private static let pin = PublicKeyPin(sha256: Data(repeating: 7, count: 32))
    private static let tailnet = HiveAddress(host: "studio.tail0000.ts.net", port: 4483)
    private static let local = HiveAddress(host: "Studio.local", port: 4483)

    @Test("Another key at a found address, with the Hive's own addresses unreachable, reads as offline")
    func impostorReadsAsOffline() async {
        // Arrange
        let connection = HiveConnection(addresses: [Self.tailnet], pin: Self.pin, discovered: [Self.local])

        // Act
        let error = await #expect(throws: URLError.self) {
            try await connection.atEachAddress(method: "GET") { address -> Int in
                if address == Self.local { throw HiveConnectionError.wrongKey }
                throw URLError(.cannotFindHost)
            }
        }

        // Assert
        #expect(error?.code == .cannotFindHost)
    }

    @Test("Another key at only a found address reads as offline")
    func onlyImpostorReadsAsOffline() async {
        // Arrange
        let connection = HiveConnection(addresses: [Self.tailnet], pin: Self.pin, discovered: [Self.local])

        // Act
        let error = await #expect(throws: URLError.self) {
            try await connection.atEachAddress(method: "GET") { address -> Int in
                if address == Self.local { throw HiveConnectionError.wrongKey }
                throw URLError(.timedOut)
            }
        }

        // Assert
        #expect(error != nil)
    }

    @Test("Another key at one of the Hive's own addresses is still the identity changing")
    func ownAddressWrongKey() async {
        // Arrange
        let connection = HiveConnection(addresses: [Self.tailnet], pin: Self.pin, discovered: [Self.local])

        // Act / Assert
        await #expect(throws: HiveConnectionError.wrongKey) {
            try await connection.atEachAddress(method: "GET") { address -> Int in
                if address == Self.local { throw URLError(.cannotConnectToHost) }
                throw HiveConnectionError.wrongKey
            }
        }
    }

    @Test("A found address is tried first, and the one that answered is tried first next time")
    func triesFoundFirstThenLastThatWorked() async throws {
        // Arrange
        let connection = HiveConnection(addresses: [Self.tailnet], pin: Self.pin, discovered: [Self.local])
        var tried: [HiveAddress] = []

        // Act
        _ = try await connection.atEachAddress(method: "GET") { address -> Int in
            tried.append(address)
            if address == Self.local { throw URLError(.cannotConnectToHost) }
            return 1
        }
        _ = try await connection.atEachAddress(method: "GET") { address -> Int in
            tried.append(address)
            return 1
        }

        // Assert
        #expect(tried == [Self.local, Self.tailnet, Self.tailnet])
    }

    @Test("A found address that's already one of the Hive's own is tried once")
    func duplicateTriedOnce() async {
        // Arrange
        let connection = HiveConnection(addresses: [Self.local], pin: Self.pin)
        connection.useDiscoveredAddresses([Self.local])
        var tried: [HiveAddress] = []

        // Act
        _ = try? await connection.atEachAddress(method: "GET") { address -> Int in
            tried.append(address)
            throw URLError(.cannotConnectToHost)
        }

        // Assert
        #expect(tried == [Self.local])
    }
}
