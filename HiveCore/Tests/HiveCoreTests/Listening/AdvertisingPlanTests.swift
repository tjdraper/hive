import Foundation
@testable import HiveCore
import HiveKit
import Testing

/// Hive advertises itself only where another device on the local network could reach it, and never
/// on loopback or a tunnel such as Tailscale's.
struct AdvertisingPlanTests {
    private static let hive = AdvertisedHive(hiveID: UUID(), name: "Studio Hive")
    private static let wiFi = LocalNetworkInterface(name: "en0", index: 4, addresses: ["192.168.1.20", "2001:db8::20"])
    private static let ethernet = LocalNetworkInterface(name: "en5", index: 9, addresses: ["10.0.0.20"])

    private static func target(_ access: NetworkAccess, advertised: AdvertisedHive? = hive) -> ListenTarget {
        ListenTarget(networkAccess: access, port: 4483, advertised: advertised)
    }

    @Test("Listening on every address advertises on every local network")
    func everyLocalNetwork() {
        // Arrange
        let hosts: Set = ["127.0.0.1", "::"]

        // Act
        let advertisement = AdvertisingPlan.advertisement(
            for: Self.target(.allAddresses),
            listeningOn: hosts,
            interfaces: [Self.wiFi, Self.ethernet]
        )

        // Assert
        #expect(advertisement == LocalNetworkAdvertisement(hive: Self.hive, port: 4483, interfaces: [4, 9]))
    }

    @Test("Listening on one address advertises only on the network it's on")
    func chosenAddressOnly() {
        // Arrange
        let hosts: Set = ["127.0.0.1", "10.0.0.20"]

        // Act
        let advertisement = AdvertisingPlan.advertisement(
            for: Self.target(.address("10.0.0.20")),
            listeningOn: hosts,
            interfaces: [Self.wiFi, Self.ethernet]
        )

        // Assert
        #expect(advertisement?.interfaces == [9])
    }

    @Test("Listening on this Mac only advertises nowhere")
    func loopbackOnly() {
        // Arrange
        let hosts: Set = ["127.0.0.1"]

        // Act
        let advertisement = AdvertisingPlan.advertisement(
            for: Self.target(.thisMacOnly),
            listeningOn: hosts,
            interfaces: [Self.wiFi, Self.ethernet]
        )

        // Assert
        #expect(advertisement == nil)
    }

    @Test("Listening only on the Tailscale address advertises nowhere")
    func tailnetOnly() {
        // Arrange
        let hosts: Set = ["127.0.0.1", "100.106.46.52"]

        // Act
        let advertisement = AdvertisingPlan.advertisement(
            for: Self.target(.address("100.106.46.52")),
            listeningOn: hosts,
            interfaces: [Self.wiFi, Self.ethernet]
        )

        // Assert
        #expect(advertisement == nil)
    }

    @Test("Turned off, Hive advertises nowhere, even listening on every address")
    func turnedOff() {
        // Arrange
        let hosts: Set = ["127.0.0.1", "::"]

        // Act
        let advertisement = AdvertisingPlan.advertisement(
            for: Self.target(.allAddresses, advertised: nil),
            listeningOn: hosts,
            interfaces: [Self.wiFi, Self.ethernet]
        )

        // Assert
        #expect(advertisement == nil)
    }

    @Test("The Mac's own interfaces leave out loopback and tunnels")
    func interfaceListLeavesOutLoopbackAndTunnels() {
        // Arrange
        let loopbackIndex = if_nametoindex("lo0")

        // Act
        let interfaces = NetworkInterfaceList.localNetworkInterfaces()

        // Assert
        #expect(!interfaces.contains { $0.index == loopbackIndex })
        #expect(!interfaces.contains { $0.name.hasPrefix("utun") })
        #expect(!interfaces.flatMap(\.addresses).contains { $0.hasPrefix("127.") })
    }
}
