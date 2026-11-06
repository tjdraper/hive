@testable import HiveCore
import HiveKit
import Testing

struct ListenPlanTests {
    private let loopback = ListenerAddress(host: "127.0.0.1", port: 4483)

    @Test("This Mac only listens on 127.0.0.1 alone")
    func thisMacOnly() {
        // Act
        let addresses = ListenPlan.addresses(for: ListenTarget(networkAccess: .thisMacOnly, port: 4483), present: ["10.0.0.8"])

        // Assert
        #expect(addresses == [loopback])
    }

    @Test("A chosen address is listened on beside 127.0.0.1 while the Mac has it")
    func chosenAddressPresent() {
        // Act
        let addresses = ListenPlan.addresses(
            for: ListenTarget(networkAccess: .address("100.106.46.52"), port: 4483),
            present: ["10.0.0.8", "100.106.46.52"]
        )

        // Assert
        #expect(addresses == [loopback, ListenerAddress(host: "100.106.46.52", port: 4483)])
    }

    @Test("A chosen address the Mac doesn't have yet leaves 127.0.0.1 alone")
    func chosenAddressAbsent() {
        // Act
        let addresses = ListenPlan.addresses(for: ListenTarget(networkAccess: .address("100.106.46.52"), port: 4483), present: ["10.0.0.8"])

        // Assert
        #expect(addresses == [loopback])
    }

    @Test("All addresses adds the dual-stack wildcard beside 127.0.0.1, on the chosen port")
    func allAddresses() {
        // Act
        let addresses = ListenPlan.addresses(for: ListenTarget(networkAccess: .allAddresses, port: 5000), present: [])

        // Assert
        #expect(addresses == [ListenerAddress(host: "127.0.0.1", port: 5000), ListenerAddress(host: "::", port: 5000)])
    }
}
