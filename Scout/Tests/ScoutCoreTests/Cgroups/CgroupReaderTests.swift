@testable import ScoutCore
import ScoutProtocol
import Testing

struct CgroupReaderTests {
    private static let database = "a8e884d03ea682e7dd9b7e1d546c1e71e1ec32c1de472afa076954dcac7a9955"
    private static let cache = "8d00a4ea2ab8cc4b9becf1158192bec77fa4212d88e46089dff6958bdba4fa6d"
    private static let site = String(repeating: "ab", count: 32)
    private static let worker = String(repeating: "cd", count: 32)

    @Test("Docker's systemd driver on cgroup v2: each container and service, memory without reclaimable cache")
    func systemdDriver() throws {
        // Arrange: Debian 12 with Docker in Swarm mode, captured with nine containers.
        let reader = CgroupReader(files: CapturedServer.debian12Swarm.files)

        // Act
        let readingResult = reader.read(elapsed: nil)
        let reading = try #require(readingResult)

        // Assert
        #expect(reading.containers.count == 9)
        #expect(Set(reading.services.map(\.name)) == [
            "console-getty.service", "containerd.service", "cron.service", "dbus.service", "docker.service", "exim4.service",
            "hive-scout.service", "polkit.service", "scout-test-fill.service", "ssh.service", "systemd-journald.service",
            "systemd-logind.service", "systemd-networkd.service", "systemd-udevd.service",
        ])
        let database = try #require(reading.containers.first { $0.name == Self.database })
        // memory.current 19,931,136 less inactive_file 14,757,888.
        #expect(database.memoryBytes == 5_173_248)
        #expect(database.processes == 2)
        #expect(database.cpuCores == nil)
        #expect(database.readBytesPerSecond == nil)
        #expect(reading.containers.first { $0.name == Self.cache }?.memoryBytes == 2_158_592 - 114_688)
        let databaseUnit = CgroupUnit(kind: .container, name: Self.database, path: "system.slice/docker-\(Self.database).scope")
        #expect(reading.unitOfProcess[1931] == databaseUnit)
        #expect(reading.unitOfProcess[115141]?.name == "cron.service")
        // udevd's process is in a cgroup of its own below its service's, so the service lists none.
        #expect(reading.services.first { $0.name == "systemd-udevd.service" }?.processes == 0)
    }

    @Test("Docker's own driver on cgroup v2, where only the cpu controller is on")
    func cgroupfsDriver() throws {
        // Arrange: Alpine 3.22 with OpenRC and two containers.
        let reader = CgroupReader(files: CapturedServer.alpine322Docker.files)

        // Act
        let readingResult = reader.read(elapsed: nil)
        let reading = try #require(readingResult)

        // Assert
        #expect(reading.services.isEmpty)
        #expect(reading.containers.map(\.name).sorted() == [
            "836895074d6a783f7f5cab6a9e6e1c17ebfbbdcbd088794194b0f8a854d1aa38",
            "e51c2cd85949707ae67e2b1095a2d09cbac466546b4c84576bc9581669bc7e1b",
        ])
        #expect(reading.containers.allSatisfy { $0.memoryBytes == nil && $0.readBytesPerSecond == nil })
        #expect(reading.containers.map(\.processes).sorted() == [1, 2])
        #expect(reading.unitOfProcess[5105]?.name == "836895074d6a783f7f5cab6a9e6e1c17ebfbbdcbd088794194b0f8a854d1aa38")
    }

    @Test("A server without cgroups has no reading")
    func noCgroups() throws {
        let reader = CgroupReader(files: CapturedServer.debian12.files)
        #expect(reader.read(elapsed: nil) == nil)
    }

    @Test("A service's CPU counts work by processes that finished between readings, and I/O adds up every disk")
    func rates() throws {
        // Arrange: cron's own process stays, while a job it started ran for 4 seconds and exited.
        let server = try TemporaryServer()
        try server.write("/sys/fs/cgroup/cgroup.controllers", "cpu io memory pids\n")
        try Self.writeV2(on: server, "system.slice/cron.service", processes: [700], cpuMicroseconds: 1_000_000, read: (100, 0))
        let reader = CgroupReader(files: server.files)
        _ = reader.read(elapsed: nil)
        try Self.writeV2(on: server, "system.slice/cron.service", processes: [700], cpuMicroseconds: 5_000_000, read: (600_100, 400_000))

        // Act
        let readingResult = reader.read(elapsed: 10)
        let reading = try #require(readingResult)

        // Assert
        let cron = try #require(reading.services.first)
        #expect(cron.cpuCores == 0.4)
        #expect(cron.readBytesPerSecond == 100_000)
        #expect(cron.writtenBytesPerSecond == 0)
    }

    @Test("A container started between readings counts all its work, and one stopped while being read is left out")
    func startedAndStopped() throws {
        // Arrange
        let server = try TemporaryServer()
        try server.write("/sys/fs/cgroup/cgroup.controllers", "cpu io memory pids\n")
        try Self.writeV2(on: server, "system.slice/cron.service", processes: [700], cpuMicroseconds: 1_000_000, read: (0, 0))
        let reader = CgroupReader(files: server.files)
        _ = reader.read(elapsed: nil)
        let site = "system.slice/docker-\(Self.site).scope"
        try Self.writeV2(on: server, site, processes: [800, 801], cpuMicroseconds: 2_000_000, read: (0, 0))
        // Listed, but its cgroup was removed before its files could be read.
        try server.write("/sys/fs/cgroup/system.slice/docker-\(Self.worker).scope/.listed", "")

        // Act
        let readingResult = reader.read(elapsed: 10)
        let reading = try #require(readingResult)

        // Assert
        #expect(reading.containers.map(\.name) == [Self.site])
        #expect(reading.containers.first?.cpuCores == 0.2)
        #expect(reading.unitOfProcess[801]?.name == Self.site)
    }

    @Test("Cgroup v1: units listed in systemd's hierarchy, with figures from cpuacct, memory and blkio")
    func version1() throws {
        // Arrange
        let server = try TemporaryServer()
        let scope = "system.slice/docker-\(Self.site).scope"
        try server.write("/sys/fs/cgroup/systemd/\(scope)/cgroup.procs", "900\n901\n")
        try server.write("/sys/fs/cgroup/systemd/system.slice/nginx.service/cgroup.procs", "950\n")
        try server.write("/sys/fs/cgroup/systemd/docker/\(Self.worker)/cgroup.procs", "990\n")
        try server.write("/sys/fs/cgroup/memory/\(scope)/memory.usage_in_bytes", "50000000\n")
        try server.write("/sys/fs/cgroup/memory/\(scope)/memory.stat", "cache 30000000\ninactive_file 1\ntotal_inactive_file 20000000\n")
        try Self.writeV1(on: server, scope, cpuNanoseconds: 1_000_000_000, read: 1_000)
        let reader = CgroupReader(files: server.files)
        _ = reader.read(elapsed: nil)
        try Self.writeV1(on: server, scope, cpuNanoseconds: 16_000_000_000, read: 51_000)

        // Act
        let readingResult = reader.read(elapsed: 10)
        let reading = try #require(readingResult)

        // Assert
        let site = try #require(reading.containers.first { $0.name == Self.site })
        #expect(site.cpuCores == 1.5)
        #expect(site.memoryBytes == 30_000_000)
        #expect(site.readBytesPerSecond == 5_000)
        #expect(site.processes == 2)
        #expect(reading.containers.map(\.name).sorted() == [Self.site, Self.worker].sorted())
        // systemd on v1 doesn't account for every service's CPU.
        let nginx = try #require(reading.services.first)
        #expect(nginx.name == "nginx.service")
        #expect(nginx.cpuCores == nil)
        #expect(reading.unitOfProcess[950]?.kind == .service)
    }

    @Test("The top 10 by CPU and the top 10 by memory are each sent once, with the count of all of them")
    func top() {
        // Arrange: CPU rises with the number and memory falls, so the two top lists don't overlap.
        let uses = (0 ..< 25).map { number in
            CgroupUse(
                name: "unit-\(number)",
                cpuCores: Double(number) / 100,
                memoryBytes: UInt64(100 - number),
                readBytesPerSecond: nil,
                writtenBytesPerSecond: nil,
                processes: 1,
                commands: []
            )
        }

        // Act
        let figures = CgroupReader.figures(of: uses, commands: ["unit-24": ["nginx", "php-fpm"]])

        // Assert
        #expect(figures.count == 25)
        #expect(Set(figures.top.map(\.name)) == Set((0 ..< 10).map { "unit-\($0)" } + (15 ..< 25).map { "unit-\($0)" }))
        #expect(figures.top.first?.name == "unit-24")
        #expect(figures.top.first?.commands == ["nginx", "php-fpm"])
    }

    @Test("A folder entry is a unit only with a container's full ID or a service's name")
    func unitNames() {
        #expect(CgroupLayout.unit(named: "docker-\(Self.site).scope", in: "system.slice")?.kind == .container)
        #expect(CgroupLayout.unit(named: "libpod-\(Self.site).scope", in: "machine.slice")?.kind == .container)
        #expect(CgroupLayout.unit(named: "libpod-conmon-\(Self.site).scope", in: "machine.slice") == nil)
        #expect(CgroupLayout.unit(named: "docker-\(Self.site.dropLast()).scope", in: "system.slice") == nil)
        #expect(CgroupLayout.unit(named: Self.site.uppercased(), in: "docker") == nil)
        #expect(CgroupLayout.unit(named: "getty@tty1.service", in: "system.slice/system-getty.slice")?.name == "getty@tty1.service")
        #expect(CgroupLayout.unit(named: "home.mount", in: "system.slice") == nil)
        #expect(CgroupLayout.unit(named: "user@1000.service", in: "machine.slice") == nil)
    }

    private static func writeV2(
        on server: TemporaryServer,
        _ path: String,
        processes: [Int],
        cpuMicroseconds: UInt64,
        read: (vda: UInt64, vdb: UInt64)
    ) throws {
        let folder = "/sys/fs/cgroup/\(path)"
        try server.write("\(folder)/cgroup.procs", processes.map { "\($0)\n" }.joined())
        try server.write("\(folder)/cpu.stat", "usage_usec \(cpuMicroseconds)\nuser_usec 0\nsystem_usec 0\n")
        try server.write("\(folder)/memory.current", "1000000\n")
        try server.write("\(folder)/memory.stat", "anon 600000\nfile 400000\ninactive_file 250000\n")
        try server.write("\(folder)/io.stat", """
        253:0 rbytes=\(read.vda) wbytes=0 rios=1 wios=0 dbytes=0 dios=0
        254:16 rbytes=\(read.vdb) wbytes=0 rios=1 wios=0 dbytes=0 dios=0

        """)
    }

    private static func writeV1(on server: TemporaryServer, _ path: String, cpuNanoseconds: UInt64, read: UInt64) throws {
        try server.write("/sys/fs/cgroup/cpuacct/\(path)/cpuacct.usage", "\(cpuNanoseconds)\n")
        try server.write("/sys/fs/cgroup/blkio/\(path)/blkio.throttle.io_service_bytes_recursive", """
        8:0 Read \(read)
        8:0 Write 0
        8:0 Sync \(read)
        8:0 Async 0
        8:0 Total \(read)
        Total \(read)

        """)
    }
}
