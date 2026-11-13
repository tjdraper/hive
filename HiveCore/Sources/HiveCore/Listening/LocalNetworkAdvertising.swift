import Foundation
import HiveKit

/// What a Hive's Bonjour advertisement names (`LocalNetworkService`).
public struct AdvertisedHive: Hashable, Sendable {
    let hiveID: UUID
    let name: String

    public init(hiveID: UUID, name: String) {
        self.hiveID = hiveID
        self.name = name
    }
}

/// One of the Mac's interfaces onto a local network, with its addresses another device could reach.
struct LocalNetworkInterface: Hashable, Sendable {
    let name: String
    let index: UInt32
    let addresses: Set<String>
}

/// The Hive, advertised at its port on each interface named by its index.
struct LocalNetworkAdvertisement: Hashable, Sendable {
    let hive: AdvertisedHive
    let port: Int
    let interfaces: Set<UInt32>
}

/// Keeps one advertisement on the local network, replacing whatever it advertised before.
protocol LocalNetworkAdvertiser: Sendable {
    /// Nil stops advertising.
    func advertise(_ advertisement: LocalNetworkAdvertisement?)
}

enum AdvertisingPlan {
    /// The local networks among `interfaces` that Hive is listening on, so a device there that finds
    /// the advertisement can reach it. `interfaces` only holds local networks: a tunnel such as
    /// Tailscale's is point-to-point, and loopback reaches nobody else, so neither is ever advertised on.
    static func advertisement(
        for target: ListenTarget,
        listeningOn hosts: Set<String>,
        interfaces: [LocalNetworkInterface]
    ) -> LocalNetworkAdvertisement? {
        guard let hive = target.advertised else { return nil }
        let listensEverywhere = hosts.contains(ListenerAddress.everyAddressHost)
        let reachable = interfaces.filter { interface in
            !interface.addresses.isEmpty && (listensEverywhere || !interface.addresses.isDisjoint(with: hosts))
        }
        guard !reachable.isEmpty else { return nil }
        return LocalNetworkAdvertisement(hive: hive, port: target.port, interfaces: Set(reachable.map(\.index)))
    }
}
