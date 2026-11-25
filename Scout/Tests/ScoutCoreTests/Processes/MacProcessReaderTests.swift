#if os(macOS)
@testable import ScoutCore
import ScoutProtocol
import Testing

struct MacProcessReaderTests {
    private static let users: [UInt32: String] = [0: "root", 501: "tj"]

    private static func mine(_ pid: Int32, _ command: String, startedAt: UInt64, cpu: UInt64, memory: UInt64) -> MacProcess {
        MacProcess(
            pid: pid,
            userID: 501,
            command: command,
            isZombie: false,
            usage: MacProcess.Usage(startTime: startedAt, cpuNanoseconds: cpu, footprintBytes: memory)
        )
    }

    private static func others(_ pid: Int32, isZombie: Bool = false) -> MacProcess {
        MacProcess(pid: pid, userID: 0, command: "launchd", isZombie: isZombie, usage: nil)
    }

    /// Two `node` processes seen at the previous reading, one that started since, one whose ID was
    /// seen but which started before then and so is another process, and two of root's.
    private static let processes = [
        mine(10, "node", startedAt: 500, cpu: 3_000_000_000, memory: 100),
        mine(11, "node", startedAt: 600, cpu: 1_500_000_000, memory: 50),
        mine(12, "Finder", startedAt: 2_000_000, cpu: 500_000_000, memory: 300),
        mine(13, "zsh", startedAt: 900, cpu: 8_000_000_000, memory: 5),
        others(1),
        others(2, isZombie: true),
    ]

    private static let previous = MacProcessReader.Previous(
        cpu: [
            MacProcessReader.ProcessID(pid: 10, startTime: 500): 1_000_000_000,
            MacProcessReader.ProcessID(pid: 11, startTime: 600): 1_000_000_000,
            MacProcessReader.ProcessID(pid: 13, startTime: 800): 7_000_000_000,
        ],
        readAt: 1_000_000
    )

    @Test("Readable processes are grouped by command and user, with their CPU since the previous reading")
    func groups() throws {
        // Act
        let figures = MacProcessReader.figures(
            of: Self.processes, previous: Self.previous, elapsed: 10, busyCores: 1, users: Self.users
        )

        // Assert: the two `node` processes used 2.5 seconds between them, and Finder all 0.5 of its
        // own since it started. `zsh` has the ID of one seen before, but started earlier, so its time
        // can't be placed and counts as none.
        let node = try #require(figures.groups.first { $0.command == "node" })
        #expect(node == ProcessGroup(command: "node", user: "tj", count: 2, cpuCores: 0.25, ownMemoryBytes: 150))
        let finder = try #require(figures.groups.first { $0.command == "Finder" })
        #expect(finder.cpuCores == 0.05)
        #expect(figures.groups.first { $0.command == "zsh" }?.cpuCores == 0)
        #expect(figures.count == 6)
        #expect(figures.zombies == 1)
    }

    @Test("Other users' processes are counted, and their CPU is what the busy cores leave")
    func otherUsers() throws {
        // Act
        let figures = MacProcessReader.figures(
            of: Self.processes, previous: Self.previous, elapsed: 10, busyCores: 1, users: Self.users
        )

        // Assert: the readable ones used 0.3 cores, of 1 busy.
        let otherUsers = try #require(figures.otherUsers)
        #expect(otherUsers.count == 2)
        #expect(abs((otherUsers.cpuCores ?? 0) - 0.7) < 1e-12)
        #expect(!figures.groups.contains { $0.user == "root" })
    }

    @Test("Other users' CPU is never less than none, when the readable ones' rounds above the total")
    func otherUsersNeverNegative() {
        // Act
        let figures = MacProcessReader.figures(
            of: Self.processes, previous: Self.previous, elapsed: 10, busyCores: 0.2, users: Self.users
        )

        // Assert
        #expect(figures.otherUsers?.cpuCores == 0)
    }

    @Test("The first reading has groups and counts but no CPU")
    func firstReading() {
        // Act
        let figures = MacProcessReader.figures(
            of: Self.processes, previous: nil, elapsed: nil, busyCores: nil, users: Self.users
        )

        // Assert
        #expect(figures.groups.allSatisfy { $0.cpuCores == nil })
        #expect(figures.otherUsers == OtherUsersProcesses(count: 2, cpuCores: nil))
    }

    @Test("Where every process is readable, as for root, there's no other users' line")
    func allReadable() {
        // Act
        let figures = MacProcessReader.figures(
            of: Array(Self.processes.prefix(4)), previous: nil, elapsed: nil, busyCores: nil, users: Self.users
        )

        // Assert
        #expect(figures.otherUsers == nil)
    }
}
#endif
