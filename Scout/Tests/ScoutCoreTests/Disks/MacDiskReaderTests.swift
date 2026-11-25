#if os(macOS)
import Foundation
@testable import ScoutCore
import ScoutProtocol
import Testing

struct MacDiskReaderTests {
    /// A Mac's internal disk's statistics, as IOKit gave them.
    private static var captured: [String: Any] {
        [
            "Bytes (Read)": NSNumber(value: 13_251_193_327_616 as UInt64),
            "Bytes (Write)": NSNumber(value: 4_510_890_422_272 as UInt64),
            "Errors (Read)": NSNumber(value: 0),
            "Errors (Write)": NSNumber(value: 0),
            "Latency Time (Read)": NSNumber(value: 0),
            "Latency Time (Write)": NSNumber(value: 0),
            "Operations (Read)": NSNumber(value: 678_681_559 as UInt64),
            "Operations (Write)": NSNumber(value: 201_240_302 as UInt64),
            "Retries (Read)": NSNumber(value: 0),
            "Retries (Write)": NSNumber(value: 0),
            "Total Time (Read)": NSNumber(value: 103_422_433_233_139 as UInt64),
            "Total Time (Write)": NSNumber(value: 9_035_077_616_905 as UInt64),
        ]
    }

    @Test("A disk's activity is worked out from IOKit's counters, with no busy share")
    func activity() throws {
        // Arrange
        let earlier = try #require(MacDiskCounters(name: "disk0", statistics: Self.captured))
        var later = earlier
        later.readBytes += 50_000_000
        later.writtenBytes += 2_000_000
        later.reads += 400
        later.writes += 150

        // Act
        let activity = try #require(later.activity(since: earlier, seconds: 10))

        // Assert
        #expect(earlier == MacDiskCounters(
            name: "disk0", readBytes: 13_251_193_327_616, writtenBytes: 4_510_890_422_272, reads: 678_681_559, writes: 201_240_302
        ))
        #expect(activity == DiskActivity(
            readBytesPerSecond: 5_000_000, writtenBytesPerSecond: 200_000, readsPerSecond: 40, writesPerSecond: 15, busy: nil
        ))
    }

    @Test("A disk whose counters went backwards, such as another taking its name, has no activity")
    func backwards() throws {
        // Arrange
        let earlier = try #require(MacDiskCounters(name: "disk6", statistics: Self.captured))
        let later = MacDiskCounters(name: "disk6", readBytes: 1_000, writtenBytes: 0, reads: 10, writes: 0)

        // Act / Assert
        #expect(later.activity(since: earlier, seconds: 10) == nil)
    }

    @Test("Disk images are left out, since the disk they're on counts their activity")
    func diskImages() {
        #expect(MacDiskCounters.isPhysical(interconnect: "Apple Fabric"))
        #expect(MacDiskCounters.isPhysical(interconnect: "USB"))
        #expect(!MacDiskCounters.isPhysical(interconnect: "Virtual Interface"))
    }
}
#endif
