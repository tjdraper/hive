import Darwin

/// An IP address in the one written form `getifaddrs` and the settings both use, so a chosen address
/// can be matched against the Mac's present ones.
enum ListenAddress {
    /// The canonical form of an address another device could reach Hive at, or nil for anything else:
    /// loopback, unspecified, link-local and multicast addresses, IPv4-mapped IPv6 ones, and names.
    static func reachable(_ text: String) -> String? {
        var ipv4 = in_addr()
        if inet_pton(AF_INET, text, &ipv4) == 1 {
            return isReachable(ipv4) ? canonical(ipv4) : nil
        }
        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, text, &ipv6) == 1 {
            return isReachable(ipv6) ? canonical(ipv6) : nil
        }
        return nil
    }

    static func isReachable(_ address: in_addr) -> Bool {
        let first = UInt8(truncatingIfNeeded: UInt32(bigEndian: address.s_addr) >> 24)
        let second = UInt8(truncatingIfNeeded: UInt32(bigEndian: address.s_addr) >> 16)
        let isLoopback = first == 127
        let isUnspecified = first == 0
        let isLinkLocal = first == 169 && second == 254
        let isMulticastOrReserved = first >= 224
        return !(isLoopback || isUnspecified || isLinkLocal || isMulticastOrReserved)
    }

    static func isReachable(_ address: in6_addr) -> Bool {
        let bytes = withUnsafeBytes(of: address) { Array($0) }
        let isUnspecifiedOrLoopback = bytes.prefix(15).allSatisfy { $0 == 0 } && bytes[15] <= 1
        let isLinkLocal = bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80
        let isMulticast = bytes[0] == 0xFF
        let isIPv4Mapped = bytes.prefix(10).allSatisfy { $0 == 0 } && bytes[10] == 0xFF && bytes[11] == 0xFF
        return !(isUnspecifiedOrLoopback || isLinkLocal || isMulticast || isIPv4Mapped)
    }

    static func canonical(_ address: in_addr) -> String {
        var address = address
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count))
        return String(validating: buffer.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self) ?? ""
    }

    static func canonical(_ address: in6_addr) -> String {
        var address = address
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count))
        return String(validating: buffer.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self) ?? ""
    }
}
