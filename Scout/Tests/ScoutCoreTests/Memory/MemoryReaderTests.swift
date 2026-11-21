@testable import ScoutCore
import ScoutProtocol
import Testing

struct MemoryReaderTests {
    @Test("Memory is read in bytes, with cache as free shows it and swap used as total less free")
    func captured() throws {
        // Arrange
        var reader = MemoryReader(files: CapturedServer.debian12.files)

        // Act
        let memoryReading = reader.read(elapsed: nil)
        let memory = try #require(memoryReading)

        // Assert
        #expect(memory.totalBytes == 8_195_968 * 1024)
        #expect(memory.availableBytes == 6_486_492 * 1024)
        #expect(memory.cacheBytes == (1308 + 987_408 + 386_640) * 1024)
        #expect(memory.swapTotalBytes == 9_244_536 * 1024)
        #expect(memory.swapUsedBytes == (9_244_536 - 9_192_800) * 1024)
        #expect(memory.swapping == nil)
    }

    @Test("Swapping is pages in and out per second since the previous reading")
    func swapping() throws {
        // Arrange
        let server = try TemporaryServer()
        try server.write("/proc/meminfo", "MemTotal: 1000 kB\nMemAvailable: 500 kB\nSwapTotal: 0 kB\n")
        try server.write("/proc/vmstat", "nr_free_pages 1\npswpin 100\npswpout 50\n")
        var reader = MemoryReader(files: server.files)
        _ = reader.read(elapsed: nil)
        try server.write("/proc/vmstat", "nr_free_pages 1\npswpin 400\npswpout 50\n")

        // Act
        let memory = reader.read(elapsed: 10)

        // Assert
        #expect(memory?.swapping == Swapping(pagesInPerSecond: 30, pagesOutPerSecond: 0))
        #expect(memory?.swapUsedBytes == 0)
    }

    @Test("Without MemAvailable, which kernels before 3.14 lack, memory isn't sent")
    func withoutAvailable() {
        #expect(MemoryInfo(parsing: "MemTotal: 1000 kB\nMemFree: 500 kB\n") == nil)
    }
}
