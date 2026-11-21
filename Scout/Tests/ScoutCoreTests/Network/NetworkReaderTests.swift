@testable import ScoutCore
import ScoutProtocol
import Testing

struct NetworkReaderTests {
    @Test(
        "Loopback and Docker's interfaces are left out, and tunnels and hand-made bridges kept",
        arguments: [
            ("eth0", true), ("enp1s0", true), ("tailscale0", true), ("wg0", true), ("br0", true), ("br-lan", true),
            ("lo", false), ("docker0", false), ("docker_gwbridge", false), ("veth48ff1ba", false), ("br-0123456789ab", false),
        ]
    )
    func reported(name: String, reported: Bool) {
        #expect(NetworkReader.isReported(name) == reported)
    }

    @Test("A long name that runs into its first figure is still read")
    func longName() throws {
        // Act
        let interface = try #require(InterfaceCounters(parsing: "tailscale-long0:1234 5 6 7 0 0 0 0 890 1 2 3 0 0 0 0"))

        // Assert
        #expect(interface == InterfaceCounters(
            name: "tailscale-long0",
            receivedBytes: 1234,
            receiveErrors: 6,
            receiveDrops: 7,
            sentBytes: 890,
            sendErrors: 2,
            sendDrops: 3
        ))
    }

    @Test("Traffic is per second since the previous reading, and none for an interface that was recreated")
    func traffic() throws {
        // Arrange
        let server = try TemporaryServer()
        let header = "Inter-|   Receive\n face |bytes\n"
        try server.write("/proc/net/dev", header + """
              lo: 999 9 0 0 0 0 0 0 999 9 0 0 0 0 0 0
            eth0: 10000 10 1 2 0 0 0 0 5000 10 0 0 0 0 0 0
            wg0: 90000 10 0 0 0 0 0 0 90000 10 0 0 0 0 0 0

            """)
        var reader = NetworkReader(files: server.files)
        let first = reader.read(elapsed: nil)
        try server.write("/proc/net/dev", header + """
              lo: 999 9 0 0 0 0 0 0 999 9 0 0 0 0 0 0
            eth0: 30000 10 1 22 0 0 0 0 9000 10 5 0 0 0 0 0
            wg0: 100 1 0 0 0 0 0 0 100 1 0 0 0 0 0 0

            """)

        // Act
        let second = reader.read(elapsed: 4)

        // Assert
        #expect(first.map(\.name) == ["eth0", "wg0"])
        #expect(first.allSatisfy { $0.traffic == nil })
        #expect(second == [
            NetworkInterfaceFigures(name: "eth0", traffic: NetworkTraffic(
                receivedBytesPerSecond: 5000,
                sentBytesPerSecond: 1000,
                receiveErrorsPerSecond: 0,
                sendErrorsPerSecond: 1.25,
                receiveDropsPerSecond: 5,
                sendDropsPerSecond: 0
            )),
            NetworkInterfaceFigures(name: "wg0", traffic: nil),
        ])
    }
}
