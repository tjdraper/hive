import NIOCore
@testable import ScoutCore
import Testing

struct HostLookupTests {
    @Test("An IP address stands for itself alone")
    func ipAddress() throws {
        // Act
        let ipv4 = try HostLookup.addresses(of: HiveAddress(host: "100.64.0.1", port: 4483))
        let ipv6 = try HostLookup.addresses(of: HiveAddress(host: "fd7a:115c:a1e0::1", port: 4484))

        // Assert
        #expect(ipv4.map(\.ipAddress) == ["100.64.0.1"])
        #expect(ipv4.map(\.port) == [4483])
        #expect(ipv6.map(\.ipAddress) == ["fd7a:115c:a1e0::1"])
    }

    @Test("Each address appears once")
    func noRepeats() throws {
        // Act
        let addresses = try HostLookup.addresses(of: HiveAddress(host: "localhost", port: 4484))

        // Assert
        #expect(!addresses.isEmpty)
        #expect(Set(addresses).count == addresses.count)
    }
}
