@testable import ScoutCore
import ScoutProtocol
import Testing

struct CPUReaderTests {
    @Test("Each captured server's CPU times and cores are read", arguments: CapturedServer.allCases)
    func captured(server: CapturedServer) throws {
        // Arrange
        let text = try #require(server.files.text(at: "/proc/stat"))

        // Act
        let times = try #require(CPUTimes(parsing: text))

        // Assert
        #expect(times.cores == 10)
        #expect(times.idle > 600_000_000)
        #expect(times.steal == 0)
    }

    @Test("Nice time counts as user time, and interrupts as system time")
    func fields() throws {
        // Arrange: user, nice, system, idle, I/O wait, irq, softirq, steal, guest, guest nice
        let earlier = try #require(CPUTimes(parsing: "cpu  90 10 40 800 30 5 5 20 0 0\ncpu0 0 0 0 0 0 0 0 0 0 0\n"))
        let later = try #require(CPUTimes(parsing: "cpu  350 50 120 1300 60 10 20 90 0 0\ncpu0 0 0 0 0 0 0 0 0 0 0\n"))

        // Act
        let use = try #require(later.use(since: earlier))

        // Assert: 1,000 ticks passed, of which 300 user, 100 system, 30 waiting and 70 stolen.
        #expect(use == CPUUse(user: 0.3, system: 0.1, ioWait: 0.03, steal: 0.07))
    }

    @Test("Idle time that went backwards counts as none, never as negative")
    func idleBackwards() throws {
        // Arrange
        let earlier = try #require(CPUTimes(parsing: "cpu  100 0 0 800 30 0 0 0\ncpu0 0 0 0 0 0 0 0 0\n"))
        let later = try #require(CPUTimes(parsing: "cpu  200 0 0 790 28 0 0 0\ncpu0 0 0 0 0 0 0 0 0\n"))

        // Act
        let use = try #require(later.use(since: earlier))

        // Assert
        #expect(use.user == 1)
        #expect(use.ioWait == 0)
    }

    @Test("The first reading has the cores and load but no use")
    func firstReading() throws {
        // Arrange
        let server = try TemporaryServer()
        try server.write("/proc/stat", "cpu  100 0 100 800 0 0 0 0\ncpu0 50 0 50 400 0 0 0 0\ncpu1 50 0 50 400 0 0 0 0\n")
        try server.write("/proc/loadavg", "0.52 1.34 2.11 1/983 5977\n")
        var reader = CPUReader(files: server.files)

        // Act
        let first = reader.read(elapsed: nil)
        try server.write("/proc/stat", "cpu  150 0 100 850 0 0 0 0\ncpu0 75 0 50 425 0 0 0 0\ncpu1 75 0 50 425 0 0 0 0\n")
        let second = reader.read(elapsed: 10)

        // Assert
        #expect(first == CPUFigures(cores: 2, use: nil, load: LoadAverages(oneMinute: 0.52, fiveMinutes: 1.34, fifteenMinutes: 2.11)))
        #expect(second?.use?.user == 0.5)
    }
}
