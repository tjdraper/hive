@testable import HiveCore
import Testing

struct ListenAddressTests {
    @Test(
        "An address another device could reach is kept, in its canonical form",
        arguments: [
            ("100.106.46.52", "100.106.46.52"),
            ("10.0.0.8", "10.0.0.8"),
            ("fd7a:115c:a1e0:0:0:0:0:1", "fd7a:115c:a1e0::1"),
            ("2001:DB8::1", "2001:db8::1"),
        ]
    )
    func keepsReachableAddress(text: String, canonical: String) {
        // Act
        let address = ListenAddress.reachable(text)

        // Assert
        #expect(address == canonical)
    }

    @Test(
        "Loopback, unspecified, link-local, multicast and mapped addresses, and names, are refused",
        arguments: [
            "127.0.0.1", "127.1.2.3", "0.0.0.0", "0.1.2.3", "169.254.1.1", "224.0.0.1", "255.255.255.255",
            "::", "::1", "fe80::1", "ff02::1", "::ffff:10.0.0.8",
            "localhost", "hive.example.com", "", "10.0.0.8:4483", " 10.0.0.8",
        ]
    )
    func refusesOtherAddresses(text: String) {
        // Act
        let address = ListenAddress.reachable(text)

        // Assert
        #expect(address == nil)
    }
}
