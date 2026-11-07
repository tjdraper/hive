import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct HostKeyScannerTests {
    private static let key = SSHKeyPair().publicKey

    @Test("Each address is tried until one answers with a key, as ssh would connect")
    func triesEachAddress() async {
        // Arrange
        let answers: [String: HostKeyScanOutcome] = ["::1": .failed(.unreachable), "127.0.0.1": .found(Self.key)]
        var tried: [String] = []

        // Act
        let outcome = await HostKeyScanner.firstFound(trying: ["::1", "127.0.0.1", "10.0.0.9"]) { address in
            tried.append(address)
            return answers[address] ?? .failed(.unreachable)
        }

        // Assert
        #expect(outcome == .found(Self.key))
        #expect(tried == ["::1", "127.0.0.1"])
    }

    @Test("A server that answered without a usable key is reported over addresses that didn't answer")
    func keepsTheTellingFailure() async {
        // Act
        let outcome = await HostKeyScanner.firstFound(trying: ["::1", "127.0.0.1", "10.0.0.9"]) { address in
            address == "127.0.0.1" ? .failed(.failed) : .failed(.unreachable)
        }

        // Assert
        #expect(outcome == .failed(.failed))
    }

    @Test("Nothing answering is unreachable")
    func unreachable() async {
        // Act
        let outcome = await HostKeyScanner.firstFound(trying: ["::1", "127.0.0.1"]) { _ in .failed(.unreachable) }

        // Assert
        #expect(outcome == .failed(.unreachable))
    }

    @Test("localhost resolves to both loopback addresses, and a numeric address to itself")
    func resolves() async {
        // Act
        let localhost = await HostAddressResolver.addresses(of: "localhost")
        let numeric = await HostAddressResolver.addresses(of: "127.0.0.1")

        // Assert
        #expect(Set(localhost) == ["::1", "127.0.0.1"])
        #expect(numeric == ["127.0.0.1"])
    }
}
