#if os(macOS)
@testable import ScoutCore
import ScoutProtocol
import Testing

struct MacNetworkReaderTests {
    private static func interface(_ name: String, flags: UInt32, routable: Bool) -> MacInterface {
        let counters = InterfaceCounters(
            name: name, receivedBytes: 0, receiveErrors: 0, receiveDrops: 0, sentBytes: 0, sendErrors: 0, sendDrops: 0
        )
        return MacInterface(name: name, flags: flags, hasRoutableAddress: routable, counters: counters)
    }

    @Test("Interfaces carrying the Mac's own traffic are reported, and the system's and virtual machines' aren't")
    func reported() {
        // Arrange: flags and addresses as a Mac with Ethernet, Wi-Fi, Tailscale and a virtual machine had them.
        let captured = [
            Self.interface("lo0", flags: 0x8049, routable: false),
            Self.interface("en0", flags: 0x8863, routable: true),
            Self.interface("en1", flags: 0x8863, routable: true),
            Self.interface("en2", flags: 0x8963, routable: false),
            Self.interface("awdl0", flags: 0x8863, routable: false),
            Self.interface("utun0", flags: 0x8051, routable: false),
            Self.interface("utun15", flags: 0x8051, routable: true),
            Self.interface("bridge0", flags: 0x8863, routable: false),
            Self.interface("bridge100", flags: 0x8A63, routable: true),
            Self.interface("vmenet0", flags: 0x8963, routable: false),
            Self.interface("en5", flags: 0x8862, routable: true),
        ]

        // Act
        let reported = captured.filter(\.isReported).map(\.name)

        // Assert: en5 isn't up.
        #expect(reported == ["en0", "en1", "utun15"])
    }

    @Test("Traffic is worked out as on Linux, without sent drops, which a Mac doesn't count")
    func traffic() throws {
        // Arrange
        let earlier = InterfaceCounters(
            name: "en0", receivedBytes: 2_135_164_928, receiveErrors: 0, receiveDrops: 0, sentBytes: 76_487_680, sendErrors: 0, sendDrops: 0
        )
        var later = earlier
        later.receivedBytes += 3_090_000
        later.sentBytes += 120_000
        later.receiveDrops += 20

        // Act
        let traffic = try #require(MacInterface.traffic(from: earlier, to: later, seconds: 10))

        // Assert
        #expect(traffic == NetworkTraffic(
            receivedBytesPerSecond: 309_000,
            sentBytesPerSecond: 12_000,
            receiveErrorsPerSecond: 0,
            sendErrorsPerSecond: 0,
            receiveDropsPerSecond: 2,
            sendDropsPerSecond: nil
        ))
    }
}
#endif
