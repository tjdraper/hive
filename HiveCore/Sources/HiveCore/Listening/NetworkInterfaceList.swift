import Darwin
import HiveKit

/// The Mac's addresses that another device could reach Hive at, read fresh each time, since interfaces
/// such as Tailscale's come and go while Hive runs.
enum NetworkInterfaceList {
    static func current() -> [NetworkInterfaceAddress] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }

        var found: [NetworkInterfaceAddress] = []
        for entry in sequence(first: first, next: { $0?.pointee.ifa_next }) {
            guard let entry = entry?.pointee,
                  entry.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING),
                  let address = Self.address(of: entry)
            else { continue }
            found.append(NetworkInterfaceAddress(interface: String(cString: entry.ifa_name), address: address))
        }
        return found.sorted { ($0.interface, $0.address) < ($1.interface, $1.address) }
    }

    static func presentAddresses() -> Set<String> {
        Set(current().map(\.address))
    }

    private static func address(of entry: ifaddrs) -> String? {
        guard let socketAddress = entry.ifa_addr else { return nil }
        switch Int32(socketAddress.pointee.sa_family) {
        case AF_INET:
            let address = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            return ListenAddress.isReachable(address) ? ListenAddress.canonical(address) : nil
        case AF_INET6:
            let address = socketAddress.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
            return ListenAddress.isReachable(address) ? ListenAddress.canonical(address) : nil
        default:
            return nil
        }
    }
}
