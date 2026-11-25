#if os(macOS)
@testable import ScoutCore
import ScoutProtocol
import Testing

struct MacCPUReaderTests {
    @Test("A Mac's use is worked out from its ticks, with no I/O wait or steal")
    func captured() throws {
        // Arrange: two readings 10 seconds apart on a Mac with 10 cores, taken from `host_statistics`.
        let earlier = MacCPUTicks(user: 103_194_037, nice: 0, system: 63_873_257, idle: 2_137_445_859)
        let later = MacCPUTicks(user: 103_194_550, nice: 0, system: 63_873_525, idle: 2_137_455_208)

        // Act
        let use = try #require(later.use(since: earlier))

        // Assert: 10,130 ticks passed, of which 513 user and 268 system.
        #expect(abs(use.user - 513.0 / 10_130) < 1e-12)
        #expect(abs(use.system - 268.0 / 10_130) < 1e-12)
        #expect(use.ioWait == nil)
        #expect(use.steal == nil)
    }

    @Test("Nice time counts as user time, and ticks that wrapped past 32 bits keep counting")
    func niceAndWrap() throws {
        // Arrange
        let earlier = MacCPUTicks(user: 4_294_967_000, nice: 100, system: 50, idle: 1_000)
        let later = MacCPUTicks(user: 104, nice: 300, system: 150, idle: 1_400)

        // Act
        let use = try #require(later.use(since: earlier))

        // Assert: user grew by 400 across the wrap and nice by 200, so 600 of 1,100 ticks.
        #expect(abs(use.user - 600.0 / 1_100) < 1e-12)
        #expect(abs(use.system - 100.0 / 1_100) < 1e-12)
    }
}
#endif
