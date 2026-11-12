import Foundation
@testable import HiveKit
import Testing

/// Beekeeper turns App Transport Security off, so nothing but this keeps its requests on HTTPS.
struct HiveAddressTests {
    @Test("Every kind of address is reached over https", arguments: [
        "hive.example.com",
        "100.115.153.27",
        "fd7a:115c:a1e0::1",
        "[fd7a:115c:a1e0::1]",
        "karrin",
    ])
    func alwaysHTTPS(host: String) throws {
        // Arrange
        let address = HiveAddress(host: host, port: 4483)

        // Act
        let url = try #require(address.url(path: "/health"))

        // Assert
        #expect(url.scheme == "https")
        #expect(url.port == 4483)
        #expect(url.path == "/health")
    }

    @Test("A host that carries its own scheme never gives a plain http URL")
    func hostWithSchemeRefused() {
        // Arrange
        let address = HiveAddress(host: "http://hive.example.com", port: 80)

        // Act
        let url = address.url(path: "/health")

        // Assert
        #expect(url == nil || url?.scheme == "https")
    }
}
