import Foundation
import NIOCore

/// Where a request came from, as rate limiting counts it. Only the connection's own address is used,
/// never a header such as `X-Forwarded-For`, which the sender chooses.
struct ClientAddress: Hashable, Sendable {
    let key: String

    init(key: String) {
        self.key = key
    }

    init(_ address: SocketAddress?) {
        switch address {
        case .v4(let ipv4):
            key = Self.ipv4Key(withUnsafeBytes(of: ipv4.address.sin_addr) { Array($0) })
        case .v6(let ipv6):
            key = Self.ipv6Key(withUnsafeBytes(of: ipv6.address.sin6_addr) { Array($0) })
        default:
            key = "other"
        }
    }

    private static func ipv4Key(_ bytes: [UInt8]) -> String {
        bytes.map(String.init).joined(separator: ".")
    }

    /// One IPv6 host is usually given a whole /64, so it counts as its /64. An IPv4 client of a dual-stack
    /// listener arrives as `::ffff:a.b.c.d`, and its /64 would lump every IPv4 client together.
    private static func ipv6Key(_ bytes: [UInt8]) -> String {
        if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
            return ipv4Key(Array(bytes.suffix(4)))
        }
        return bytes.prefix(8).map { String(format: "%02x", $0) }.joined() + "/64"
    }
}
