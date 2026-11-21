@testable import ScoutCore
import ScoutProtocol
import Testing

struct SamplerTests {
    private static let space = FilesystemSpace(
        sizeBytes: 1_000,
        usedBytes: 400,
        availableBytes: 500,
        inodes: InodeCounts(used: 10, free: 90)
    )

    @Test(
        "A captured server's first sample has every figure but the rates",
        arguments: [CapturedServer.debian12, .ubuntu2404, .alpine322, .rocky9]
    )
    func firstSample(server: CapturedServer) async throws {
        // Arrange
        var sampler = Sampler(files: server.files, filesystemSpace: FilesystemSpaceReader { _ in Self.space }, on: .shared)

        // Act
        let sample = await sampler.sample(takenAt: 1_700_000_000)

        // Assert
        #expect(sample.takenAt == 1_700_000_000)
        #expect(!sample.server.processesHidden)
        let cpu = try #require(sample.cpu)
        #expect(cpu.cores == 10)
        #expect(cpu.use == nil)
        #expect(cpu.load != nil)
        #expect(sample.memory?.totalBytes == 8_195_968 * 1024)
        #expect(sample.memory?.swapping == nil)
        #expect(sample.pressure == nil)
        #expect(sample.filesystems == [FilesystemFigures(mountPoint: "/etc/hosts", device: "/dev/vdb1", type: "btrfs", space: Self.space)])
        #expect(sample.disks.map(\.name).sorted() == ["vda", "vdb", "vdc"])
        #expect(sample.networkInterfaces.map(\.name) == ["eth0"])
        #expect(sample.processes?.count == 11)
    }

    @Test("Where processes are hidden, that's reported and everything else is sent")
    func hidden() async throws {
        // Arrange
        var sampler = Sampler(files: CapturedServer.debian12Hidepid.files, filesystemSpace: FilesystemSpaceReader { _ in nil }, on: .shared)

        // Act
        let sample = await sampler.sample(takenAt: 0)

        // Assert
        #expect(sample.server.processesHidden)
        #expect(sample.processes == nil)
        #expect(sample.cpu != nil)
        #expect(sample.memory != nil)
        #expect(sample.disks.count == 3)
    }
}
