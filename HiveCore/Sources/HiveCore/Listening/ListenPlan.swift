import HiveKit

struct ListenerAddress: Hashable, Sendable {
    static let loopbackHost = "127.0.0.1"
    /// Dual-stack, since SwiftNIO turns off `IPV6_V6ONLY`, so it takes IPv4 connections too.
    static let everyAddressHost = "::"

    let host: String
    let port: Int

    var isLoopback: Bool {
        host == Self.loopbackHost
    }
}

/// What the listening settings ask for.
public struct ListenTarget: Hashable, Sendable {
    let networkAccess: NetworkAccess
    let port: Int

    public init(networkAccess: NetworkAccess, port: Int) {
        self.networkAccess = networkAccess
        self.port = port
    }
}

extension HiveSettings {
    public var listenTarget: ListenTarget {
        ListenTarget(networkAccess: networkAccess, port: port)
    }
}

enum ListenPlan {
    /// Always `127.0.0.1`, so Beekeeper on the Hive Mac keeps working whatever the setting. A chosen
    /// address is only listened on while the Mac has it, since binding an absent address fails.
    static func addresses(for target: ListenTarget, present: Set<String>) -> Set<ListenerAddress> {
        var addresses: Set = [ListenerAddress(host: ListenerAddress.loopbackHost, port: target.port)]
        switch target.networkAccess {
        case .thisMacOnly:
            break
        case .address(let address):
            if present.contains(address) { addresses.insert(ListenerAddress(host: address, port: target.port)) }
        case .allAddresses:
            addresses.insert(ListenerAddress(host: ListenerAddress.everyAddressHost, port: target.port))
        }
        return addresses
    }
}
