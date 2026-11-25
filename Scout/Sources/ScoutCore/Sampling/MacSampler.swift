#if os(macOS)
import Darwin
import ScoutProtocol

/// Takes a Mac's samples, with the same figures as a Linux server's where a Mac has them. Pressure,
/// containers and services are Linux's own, so they're left out rather than faked. It keeps the
/// previous readings that rates are worked out from, so one sampler serves a run of samples.
public struct MacSampler {
    private let eventLoop: ScoutEventLoop
    private let filesystems = MacFilesystemReader()
    private var cpu = MacCPUReader()
    private var memory = MacMemoryReader()
    private var disks = MacDiskReader()
    private var network = MacNetworkReader()
    private var processes = MacProcessReader()
    private var previousTime: ReadingTime?

    public init(on eventLoop: ScoutEventLoop = .shared) {
        self.eventLoop = eventLoop
    }

    /// - Parameter takenAt: the sample's mark, in seconds since 1970.
    public mutating func sample(takenAt: Int64) async -> MetricsSample {
        let time = Self.readingTime()
        let elapsed = time?.seconds(since: previousTime)
        previousTime = time

        let cpu = cpu.read(elapsed: elapsed)
        let memory = memory.read(elapsed: elapsed)
        let busyCores = cpu.flatMap { cpu in cpu.use.map { ($0.user + $0.system) * Double(cpu.cores) } }
        let processes = processes.read(elapsed: elapsed, busyCores: busyCores)
        let disks = disks.read(elapsed: elapsed)
        let network = network.read(elapsed: elapsed)
        // Last, since a filesystem that doesn't answer holds the sample up until it times out.
        let filesystems = await filesystems.read(on: eventLoop)

        return MetricsSample(
            takenAt: takenAt,
            server: MacServerFactsReader.read(),
            cpu: cpu,
            memory: memory,
            pressure: nil,
            filesystems: filesystems,
            disks: disks,
            networkInterfaces: network,
            processes: processes
        )
    }

    /// By the clock that keeps counting while the Mac sleeps, so rates after a sleep are over the
    /// whole time since the previous reading. `kern.bootsessionuuid` is new each time the Mac starts.
    private static func readingTime() -> ReadingTime? {
        var now = timespec()
        guard clock_gettime(CLOCK_MONOTONIC, &now) == 0 else { return nil }
        let uptime = Double(now.tv_sec) + Double(now.tv_nsec) / 1_000_000_000
        return ReadingTime(bootID: MacSysctl.string("kern.bootsessionuuid"), uptimeSeconds: uptime)
    }
}
#endif
