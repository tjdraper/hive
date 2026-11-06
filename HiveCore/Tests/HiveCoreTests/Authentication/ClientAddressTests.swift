@testable import HiveCore
import NIOCore
import Testing

struct ClientAddressTests {
    @Test("Each IPv4 address counts on its own")
    func ipv4AddressesAreSeparate() throws {
        // Act
        let first = ClientAddress(try SocketAddress(ipAddress: "192.0.2.1", port: 50000))
        let second = ClientAddress(try SocketAddress(ipAddress: "192.0.2.2", port: 50000))

        // Assert
        #expect(first != second)
    }

    @Test("The port doesn't make a new address")
    func portIsIgnored() throws {
        // Act
        let first = ClientAddress(try SocketAddress(ipAddress: "192.0.2.1", port: 50000))
        let second = ClientAddress(try SocketAddress(ipAddress: "192.0.2.1", port: 50001))

        // Assert
        #expect(first == second)
    }

    @Test("IPv6 addresses in the same /64 count as one, and other /64s apart")
    func ipv6CountsBySlash64() throws {
        // Act
        let first = ClientAddress(try SocketAddress(ipAddress: "2001:db8:1:2::1", port: 1))
        let sameNetwork = ClientAddress(try SocketAddress(ipAddress: "2001:db8:1:2:ffff::9", port: 1))
        let otherNetwork = ClientAddress(try SocketAddress(ipAddress: "2001:db8:1:3::1", port: 1))

        // Assert
        #expect(first == sameNetwork)
        #expect(first != otherNetwork)
    }

    @Test("IPv4 clients of a dual-stack listener count by their IPv4 address, not as one /64")
    func mappedIPv4CountsAsIPv4() throws {
        // Act
        let mapped = ClientAddress(try SocketAddress(ipAddress: "::ffff:192.0.2.1", port: 1))
        let otherMapped = ClientAddress(try SocketAddress(ipAddress: "::ffff:192.0.2.2", port: 1))
        let plain = ClientAddress(try SocketAddress(ipAddress: "192.0.2.1", port: 1))

        // Assert
        #expect(mapped == plain)
        #expect(mapped != otherMapped)
    }
}
