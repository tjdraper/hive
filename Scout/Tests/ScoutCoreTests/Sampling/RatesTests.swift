@testable import ScoutCore
import ScoutProtocol
import Testing

struct RatesTests {
    @Test("Time between readings comes from the kernel's clock, and none is given across a restart")
    func readingTime() {
        // Arrange
        let earlier = ReadingTime(bootID: "a", uptimeSeconds: 1_000)

        // Act, Assert
        #expect(ReadingTime(bootID: "a", uptimeSeconds: 1_010.5).seconds(since: earlier) == 10.5)
        #expect(ReadingTime(bootID: "b", uptimeSeconds: 1_010).seconds(since: earlier) == nil)
        // A server that restarted and has been up longer since still started again.
        #expect(ReadingTime(bootID: "b", uptimeSeconds: 5_000).seconds(since: earlier) == nil)
        #expect(ReadingTime(bootID: "a", uptimeSeconds: 1_000).seconds(since: earlier) == nil)
        #expect(ReadingTime(bootID: "a", uptimeSeconds: 1_010).seconds(since: nil) == nil)
    }

    @Test("A 32-bit counter that wrapped counts what it grew by, and a 64-bit one that went backwards counts nothing")
    func counters() {
        #expect(CounterIncrease.of32Bit(4_294_967_000, to: 704) == 1_000)
        #expect(CounterIncrease.of32Bit(500, to: 1_500) == 1_000)
        #expect(CounterIncrease.of(1_500, to: 500) == nil)
        #expect(CounterIncrease.perSecond(500, to: 1_500, seconds: 4) == 250)
    }

    @Test("A server that restarted between samples gives no rates, though its counters started again")
    func restart() async throws {
        // Arrange
        let server = try TemporaryServer()
        try server.writeClock(uptime: 50_000, bootID: "before")
        try server.write("/proc/stat", "cpu  9000 0 4000 80000 100 0 0 0 0 0\ncpu0 9000 0 4000 80000 100 0 0 0 0 0\n")
        try server.write("/proc/vmstat", "pswpin 9000\npswpout 9000\n")
        try server.write("/proc/meminfo", "MemTotal: 1000 kB\nMemAvailable: 500 kB\n")
        try server.write("/proc/net/dev", "h\nh\n  eth0: 90000 1 0 0 0 0 0 0 90000 1 0 0 0 0 0 0\n")
        var sampler = Sampler(files: server.files, filesystemSpace: FilesystemSpaceReader { _ in nil }, on: .shared)
        _ = await sampler.sample(takenAt: 0)

        try server.writeClock(uptime: 60, bootID: "after")
        try server.write("/proc/stat", "cpu  30 0 20 5000 0 0 0 0 0 0\ncpu0 30 0 20 5000 0 0 0 0 0 0\n")
        try server.write("/proc/vmstat", "pswpin 0\npswpout 0\n")
        try server.write("/proc/net/dev", "h\nh\n  eth0: 100 1 0 0 0 0 0 0 100 1 0 0 0 0 0 0\n")

        // Act
        let sample = await sampler.sample(takenAt: 10)

        // Assert
        #expect(sample.cpu?.use == nil)
        #expect(sample.memory != nil)
        #expect(sample.memory?.swapping == nil)
        #expect(sample.networkInterfaces.map(\.traffic) == [nil])

        // And the sample after has them again.
        try server.writeClock(uptime: 70, bootID: "after")
        try server.write("/proc/stat", "cpu  130 0 20 5900 0 0 0 0 0 0\ncpu0 130 0 20 5900 0 0 0 0 0 0\n")
        let next = await sampler.sample(takenAt: 20)
        #expect(next.cpu?.use?.user == 0.1)
        #expect(next.networkInterfaces.first?.traffic?.receivedBytesPerSecond == 0)
    }
}
