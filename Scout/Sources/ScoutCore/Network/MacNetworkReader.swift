#if os(macOS)
import Darwin
import ScoutProtocol

/// A Mac's network interface: its flags, whether it has an address another machine could reach, and
/// its 64-bit counters from `NET_RT_IFLIST2`. `getifaddrs`' own counters are 32 bits and wrap at 4 GB.
struct MacInterface: Equatable {
    var name: String
    /// `IFF_` flags.
    var flags: UInt32
    var hasRoutableAddress: Bool
    var counters: InterfaceCounters

    /// Interfaces that are up and carry the Mac's own traffic: those with an address that isn't
    /// loopback or link-local, such as Ethernet, Wi-Fi and Tailscale's. The system keeps many more
    /// up with only link-local addresses, such as AirDrop's (`awdl0`) and idle tunnels. The bridges
    /// and links virtual machines get (`bridge100` and up, `vmenet`) are left out, as Docker's are on
    /// Linux, since the Mac's own interfaces carry their traffic too.
    var isReported: Bool {
        let isUp = flags & UInt32(IFF_UP) != 0 && flags & UInt32(IFF_RUNNING) != 0
        let isLoopback = flags & UInt32(IFF_LOOPBACK) != 0
        return isUp && !isLoopback && hasRoutableAddress && !Self.isVirtualMachines(name)
    }

    static func isVirtualMachines(_ name: String) -> Bool {
        if name.hasPrefix("vmenet") { return true }
        guard name.hasPrefix("bridge"), let number = Int(name.dropFirst("bridge".count)) else { return false }
        return number >= 100
    }

    /// A Mac doesn't count sent drops for each interface, so they're left out.
    static func traffic(from earlier: InterfaceCounters, to current: InterfaceCounters, seconds: Double) -> NetworkTraffic? {
        var traffic = NetworkReader.traffic(from: earlier, to: current, seconds: seconds)
        traffic?.sendDropsPerSecond = nil
        return traffic
    }

    static func all() -> [MacInterface] {
        let addresses = interfaceAddresses()
        return withCounters(names: addresses.names).map { interface in
            var interface = interface
            interface.hasRoutableAddress = addresses.routable.contains(interface.name)
            return interface
        }
    }

    /// Each interface's name by its index, from its link-layer address, and the names of those with a
    /// routable address. `if_indextoname` reads the whole list again for each interface, which on a Mac
    /// with dozens of them cost more than the rest of a sample.
    private static func interfaceAddresses() -> (names: [UInt16: String], routable: Set<String>) {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return ([:], []) }
        defer { freeifaddrs(first) }
        var names: [UInt16: String] = [:]
        var routable: Set<String> = []
        var next = first
        while let entry = next?.pointee {
            next = entry.ifa_next
            guard let address = entry.ifa_addr else { continue }
            switch Int32(address.pointee.sa_family) {
            case AF_LINK:
                let index = UnsafeRawPointer(address).loadUnaligned(as: sockaddr_dl.self).sdl_index
                names[index] = String(cString: entry.ifa_name)
            case AF_INET:
                let ipv4 = UnsafeRawPointer(address).loadUnaligned(as: sockaddr_in.self).sin_addr.s_addr
                // 169.254.0.0/16, in network order.
                if ipv4 & 0xFFFF != 0xFEA9 { routable.insert(String(cString: entry.ifa_name)) }
            case AF_INET6:
                let ipv6 = UnsafeRawPointer(address).loadUnaligned(as: sockaddr_in6.self).sin6_addr
                // fe80::/10
                let isLinkLocal = ipv6.__u6_addr.__u6_addr8.0 == 0xFE && ipv6.__u6_addr.__u6_addr8.1 & 0xC0 == 0x80
                if !isLinkLocal { routable.insert(String(cString: entry.ifa_name)) }
            default:
                continue
            }
        }
        return (names, routable)
    }

    /// Each interface's `if_msghdr2`, whose `if_data64` holds 64-bit counters, before its addresses are known.
    private static func withCounters(names: [UInt16: String]) -> [MacInterface] {
        var request: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&request, UInt32(request.count), nil, &length, nil, 0) == 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&request, UInt32(request.count), &buffer, &length, nil, 0) == 0 else { return [] }

        var interfaces: [MacInterface] = []
        buffer.withUnsafeBytes { bytes in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                defer { offset += Int(header.ifm_msglen) }
                guard Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length else { continue }
                let message = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                guard let interfaceName = names[message.ifm_index] else { continue }
                let data = message.ifm_data
                let counters = InterfaceCounters(
                    name: interfaceName,
                    receivedBytes: data.ifi_ibytes,
                    receiveErrors: data.ifi_ierrors,
                    receiveDrops: data.ifi_iqdrops,
                    sentBytes: data.ifi_obytes,
                    sendErrors: data.ifi_oerrors,
                    sendDrops: 0
                )
                interfaces.append(MacInterface(
                    name: interfaceName, flags: UInt32(bitPattern: message.ifm_flags), hasRoutableAddress: false, counters: counters
                ))
            }
        }
        return interfaces
    }
}

/// Reads each of a Mac's interfaces' traffic, keeping the previous counters it's worked out from.
struct MacNetworkReader {
    private var previous: [String: InterfaceCounters] = [:]

    /// - Parameter elapsed: seconds since the previous reading, nil when there's none to compare with.
    mutating func read(elapsed: Double?) -> [NetworkInterfaceFigures] {
        let interfaces = MacInterface.all().filter(\.isReported).map(\.counters).sorted { $0.name < $1.name }
        defer { previous = Dictionary(interfaces.map { ($0.name, $0) }) { first, _ in first } }
        return interfaces.map { interface in
            let traffic = elapsed.flatMap { seconds in
                previous[interface.name].flatMap { MacInterface.traffic(from: $0, to: interface, seconds: seconds) }
            }
            return NetworkInterfaceFigures(name: interface.name, traffic: traffic)
        }
    }
}
#endif
