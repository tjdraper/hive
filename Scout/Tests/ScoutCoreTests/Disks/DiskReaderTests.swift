@testable import ScoutCore
import ScoutProtocol
import Testing

struct DiskReaderTests {
    @Test("Whole disks are sent, and the kernel's virtual ones, such as loop and RAM disks, aren't", arguments: CapturedServer.allCases)
    func disks(server: CapturedServer) {
        // Arrange
        var reader = DiskReader(files: server.files)

        // Act
        let disks = reader.read(elapsed: nil)

        // Assert: the captures list loop0–3, nbd0–3, vda, vdb, vdc and zram0.
        #expect(disks.map(\.name).sorted() == ["vda", "vdb", "vdc"])
        #expect(disks.allSatisfy { $0.activity == nil })
    }

    @Test("A disk's line is read by position, past the discard and flush figures newer kernels add")
    func parsing() throws {
        // Arrange
        let line: Substring = " 254      16 vdb 2606331 50964 510729717 54475 611985 442510 92488408 299357 0 639607 608722"
            + " 140502 0 51708696 21153 157838 233736"

        // Act
        let counters = try #require(DiskCounters(parsing: line))

        // Assert
        #expect(counters == DiskCounters(
            name: "vdb",
            reads: 2_606_331,
            sectorsRead: 510_729_717,
            writes: 611_985,
            sectorsWritten: 92_488_408,
            millisecondsBusy: 639_607
        ))
    }

    @Test("Activity is per second in bytes of 512-byte sectors, and time busy survives its counter wrapping")
    func activity() throws {
        // Arrange
        let earlier = DiskCounters(
            name: "sda",
            reads: 1_000,
            sectorsRead: 8_000,
            writes: 50,
            sectorsWritten: 400,
            millisecondsBusy: 4_294_967_000
        )
        let later = DiskCounters(name: "sda", reads: 1_200, sectorsRead: 10_000, writes: 150, sectorsWritten: 4_400, millisecondsBusy: 704)

        // Act
        let activity = try #require(later.activity(since: earlier, seconds: 10))

        // Assert
        #expect(activity == DiskActivity(
            readBytesPerSecond: 102_400,
            writtenBytesPerSecond: 204_800,
            readsPerSecond: 20,
            writesPerSecond: 10,
            busy: 0.1
        ))
    }

    @Test("A disk whose counts went backwards, as when another took its name, has no activity that sample")
    func replaced() {
        let earlier = DiskCounters(name: "sdb", reads: 1_000, sectorsRead: 8_000, writes: 50, sectorsWritten: 400, millisecondsBusy: 900)
        let later = DiskCounters(name: "sdb", reads: 10, sectorsRead: 80, writes: 5, sectorsWritten: 40, millisecondsBusy: 9)
        #expect(later.activity(since: earlier, seconds: 10) == nil)
    }
}
