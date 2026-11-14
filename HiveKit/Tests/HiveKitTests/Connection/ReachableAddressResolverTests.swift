import Foundation
@testable import HiveKit
import Testing

struct ReachableAddressResolverTests {
    private static let tailnet = HiveAddress(host: "studio.tail0000.ts.net", port: 4483)
    private static let lan = HiveAddress(host: "192.168.1.20", port: 4483)
    private static let local = HiveAddress(host: "Studio.local", port: 4483)

    private static func own(_ address: HiveAddress) -> ReachableAddressResolver.Candidate {
        .init(address: address, isDiscovered: false)
    }

    private static func found(_ address: HiveAddress) -> ReachableAddressResolver.Candidate {
        .init(address: address, isDiscovered: true)
    }

    @Test("An address that never answers doesn't hold up one that does")
    func unansweredAddressDoesNotHoldUpOthers() async throws {
        // Arrange
        let resolver = ReachableAddressResolver(candidates: [Self.own(Self.lan), Self.own(Self.tailnet)]) { address in
            if address == Self.lan { try await Task.sleep(for: .seconds(60)) }
        }
        let started = ContinuousClock.now

        // Act
        let address = try await resolver.firstToAnswer()

        // Assert
        #expect(address == Self.tailnet)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test("Another key at a found address, with the Hive's own addresses unreachable, reads as offline")
    func impostorReadsAsOffline() async {
        // Arrange
        let resolver = ReachableAddressResolver(candidates: [Self.found(Self.local), Self.own(Self.tailnet)]) { address in
            if address == Self.local { throw HiveConnectionError.wrongKey }
            throw URLError(.cannotFindHost)
        }

        // Act / Assert
        await #expect(throws: URLError.self) { try await resolver.firstToAnswer() }
    }

    @Test("Another key at only a found address reads as offline")
    func onlyImpostorReadsAsOffline() async {
        // Arrange
        let resolver = ReachableAddressResolver(candidates: [Self.found(Self.local)]) { _ in
            throw HiveConnectionError.wrongKey
        }

        // Act / Assert
        await #expect(throws: URLError.self) { try await resolver.firstToAnswer() }
    }

    @Test("Another key at one of the Hive's own addresses, with none answering, is the identity changing")
    func ownAddressWrongKey() async {
        // Arrange
        let resolver = ReachableAddressResolver(candidates: [Self.found(Self.local), Self.own(Self.tailnet)]) { address in
            if address == Self.local { throw URLError(.cannotConnectToHost) }
            throw HiveConnectionError.wrongKey
        }

        // Act / Assert
        await #expect(throws: HiveConnectionError.wrongKey) { try await resolver.firstToAnswer() }
    }

    @Test("Another key at one of the Hive's own addresses is passed over when another answers")
    func ownAddressWrongKeyPassedOver() async throws {
        // Arrange
        let resolver = ReachableAddressResolver(candidates: [Self.own(Self.lan), Self.own(Self.tailnet)]) { address in
            if address == Self.lan { throw HiveConnectionError.wrongKey }
        }

        // Act
        let address = try await resolver.firstToAnswer()

        // Assert
        #expect(address == Self.tailnet)
    }

    @Test("No addresses is an invalid address")
    func noAddresses() async {
        // Arrange
        let resolver = ReachableAddressResolver(candidates: []) { _ in Issue.record("Nothing to ask") }

        // Act / Assert
        await #expect(throws: HiveConnectionError.invalidAddress) { try await resolver.firstToAnswer() }
    }
}
