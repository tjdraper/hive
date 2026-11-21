#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
@testable import ScoutCore
import ScoutProtocol
import Testing

struct ProcessReaderTests {
    private static let pageSize: UInt64 = 4096

    private static func reader(for server: TemporaryServer) -> ProcessReader {
        ProcessReader(files: server.files, pageSize: pageSize, clockTicksPerSecond: 100)
    }

    /// The test's files are owned by whoever runs it, so that's the user every process runs as.
    private static func writeUsers(on server: TemporaryServer) throws {
        try server.write("/etc/passwd", "www-data:x:\(getuid()):33::/var/www:/usr/sbin/nologin\nnobody:x:65534:65534::/:/bin/false\n")
    }

    @Test(
        "Each captured server's processes and zombies are counted",
        arguments: [CapturedServer.debian12, .ubuntu2404, .alpine322, .rocky9]
    )
    func captured(server: CapturedServer) throws {
        // Arrange
        var reader = ProcessReader(files: server.files, pageSize: Self.pageSize, clockTicksPerSecond: 100)

        // Act
        let processesReading = reader.read(at: nil, elapsed: nil)
        let processes = try #require(processesReading)

        // Assert: nine sleeping, one exited and not yet collected, and the shell that started them.
        #expect(processes.count == 11)
        #expect(processes.zombies == 1)
        #expect(processes.groups.map(\.command).sorted() == ["sh", "sleep"])
        #expect(processes.groups.first { $0.command == "sleep" }?.count == 10)
        #expect(processes.groups.allSatisfy { $0.cpuCores == nil })
    }

    @Test("Forty workers of one command are one line with their total, and shared memory counts for none of them")
    func grouping() throws {
        // Arrange: each worker has 3,000 pages resident, 2,500 of them shared with the others.
        let server = try TemporaryServer()
        try Self.writeUsers(on: server)
        try server.writeClock(uptime: 1_000)
        for pid in 100..<140 {
            try server.writeProcess(pid: pid, command: "php-fpm: pool www", cpuTicks: (500, 0), startTicks: 100, pages: (3_000, 2_500))
        }
        try server.writeProcess(pid: 200, command: "nginx", cpuTicks: (50, 0), startTicks: 100, pages: (900, 100))
        var reader = Self.reader(for: server)
        _ = reader.read(at: ReadingTime(bootID: nil, uptimeSeconds: 1_000), elapsed: nil)

        // Each worker used 15 ticks of user time and 5 of system time in 10 seconds.
        for pid in 100..<140 {
            try server.writeProcess(pid: pid, command: "php-fpm: pool www", cpuTicks: (515, 5), startTicks: 100, pages: (3_000, 2_500))
        }

        // Act
        let processesReading = reader.read(at: ReadingTime(bootID: nil, uptimeSeconds: 1_010), elapsed: 10)
        let processes = try #require(processesReading)

        // Assert
        let workers = try #require(processes.groups.first { $0.command == "php-fpm: pool www" })
        #expect(workers.count == 40)
        #expect(workers.user == "www-data")
        #expect(workers.ownMemoryBytes == 40 * 500 * Self.pageSize)
        #expect(abs((workers.cpuCores ?? 0) - 0.8) < 1e-9)
        let nginx = try #require(processes.groups.first { $0.command == "nginx" })
        #expect(nginx.ownMemoryBytes == 800 * Self.pageSize)
        #expect(nginx.cpuCores == 0)
        #expect(processes.count == 41)
    }

    @Test("A process given the ID of one that exited counts its own CPU time, never a negative share")
    func reusedID() throws {
        // Arrange
        let server = try TemporaryServer()
        try Self.writeUsers(on: server)
        try server.writeProcess(pid: 300, command: "convert", cpuTicks: (1_000, 0), startTicks: 500, pages: (10, 0))
        var reader = Self.reader(for: server)
        _ = reader.read(at: ReadingTime(bootID: nil, uptimeSeconds: 10), elapsed: nil)

        // The first exited, and another started 15 seconds after the server did, at 1,500 ticks.
        try server.writeProcess(pid: 300, command: "convert", cpuTicks: (30, 0), startTicks: 1_500, pages: (10, 0))

        // Act
        let processesReading = reader.read(at: ReadingTime(bootID: nil, uptimeSeconds: 20), elapsed: 10)
        let processes = try #require(processesReading)

        // Assert: 30 ticks are 0.3 seconds of CPU time in 10 seconds.
        #expect(processes.groups.first?.cpuCores == 0.03)
    }

    @Test("A process first seen after the previous reading, though it started before, counts none of its earlier time")
    func seenLate() throws {
        // Arrange
        let server = try TemporaryServer()
        try Self.writeUsers(on: server)
        try server.writeProcess(pid: 1, command: "systemd", cpuTicks: (10, 0), startTicks: 1, pages: (10, 0))
        var reader = Self.reader(for: server)
        _ = reader.read(at: ReadingTime(bootID: nil, uptimeSeconds: 10), elapsed: nil)
        try server.writeProcess(pid: 400, command: "postgres", cpuTicks: (9_000, 0), startTicks: 200, pages: (10, 0))

        // Act
        let processesReading = reader.read(at: ReadingTime(bootID: nil, uptimeSeconds: 20), elapsed: 10)
        let processes = try #require(processesReading)

        // Assert
        #expect(processes.groups.first { $0.command == "postgres" }?.cpuCores == 0)
    }

    @Test("A process that exits between being listed and being read is skipped")
    func vanished() throws {
        // Arrange: one process's folder is listed but its memory file is gone, another's folder is empty.
        let server = try TemporaryServer()
        try Self.writeUsers(on: server)
        try server.writeProcess(pid: 500, command: "cron", cpuTicks: (1, 0), startTicks: 1, pages: (10, 0))
        try server.writeProcess(pid: 501, command: "sh", cpuTicks: (1, 0), startTicks: 1, pages: (10, 0))
        try server.remove("/proc/501/statm")
        try server.write("/proc/502/.keep", "")
        try server.remove("/proc/502/.keep")
        var reader = Self.reader(for: server)

        // Act
        let processesReading = reader.read(at: nil, elapsed: nil)
        let processes = try #require(processesReading)

        // Assert
        #expect(processes.count == 1)
        #expect(processes.groups.map(\.command) == ["cron"])
    }

    @Test("A kernel thread is counted with no memory, without reading a memory file for it")
    func kernelThread() throws {
        // Arrange: flags 0x208040, as kworker threads have, and no statm, so reading one would skip it.
        let server = try TemporaryServer()
        try Self.writeUsers(on: server)
        try server.write("/proc/7/stat", "7 (kworker/0:1-events) I 2 0 0 0 -1 2129984 0 0 0 0 0 12 0 0 20 0 1 0 25 0 0\n")

        var reader = Self.reader(for: server)

        // Act
        let processesReading = reader.read(at: nil, elapsed: nil)
        let processes = try #require(processesReading)

        // Assert
        #expect(processes.count == 1)
        #expect(processes.groups.map(\.command) == ["kworker/0:1-events"])
        #expect(processes.groups.first?.ownMemoryBytes == 0)
    }

    @Test("The top ten groups by CPU and the top ten by memory are sent, each once")
    func topGroups() throws {
        // Arrange: 25 commands. 0–9 are the busiest, and 0 and 10–18 the largest.
        let server = try TemporaryServer()
        try Self.writeUsers(on: server)
        let writeProcesses = { (reading: UInt64) in
            for index in 0..<25 {
                let large = index == 0 || (10...18).contains(index)
                try server.writeProcess(
                    pid: 1_000 + index,
                    command: "command-\(index)",
                    cpuTicks: (index < 10 ? reading * (10 + UInt64(index)) : 0, 0),
                    startTicks: 1,
                    pages: (large ? 10_000 + UInt64(index) : 10, 0)
                )
            }
        }
        try writeProcesses(1)
        var reader = Self.reader(for: server)
        _ = reader.read(at: ReadingTime(bootID: nil, uptimeSeconds: 10), elapsed: nil)
        try writeProcesses(2)

        // Act
        let processesReading = reader.read(at: ReadingTime(bootID: nil, uptimeSeconds: 20), elapsed: 10)
        let processes = try #require(processesReading)

        // Assert
        #expect(processes.groups.map(\.command).sorted() == (0...18).map { "command-\($0)" }.sorted())
        #expect(processes.count == 25)
    }

    @Test("User names come from /etc/passwd, the first for each number")
    func userNames() {
        let names = UserNames.names(parsing: """
            root:x:0:0:root:/root:/bin/bash
            toor:x:0:0::/root:/bin/sh
            # not a user
            :x:5:5::/:/bin/sh
            www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
            """)
        #expect(names == [0: "root", 33: "www-data"])
    }
}
