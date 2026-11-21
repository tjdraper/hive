import ScoutProtocol

/// Samples with the figures a test sets and the rest plausible.
enum TestSamples {
    /// On a minute mark, so a sample's minute is easy to work out.
    static let start: Int64 = 1_800_000_000

    static func sample(
        at takenAt: Int64,
        cpuUser: Double? = 0.25,
        availableBytes: UInt64 = 4_000_000_000,
        rootAvailableBytes: UInt64 = 50_000_000_000,
        dataDisk: Bool = false
    ) -> MetricsSample {
        var filesystems = [filesystem("/", available: rootAvailableBytes)]
        if dataDisk { filesystems.append(filesystem("/data", available: 900_000_000_000)) }
        return MetricsSample(
            takenAt: takenAt,
            server: ServerFacts(
                uptimeSeconds: 1_000,
                distribution: "Debian GNU/Linux 12 (bookworm)",
                kernel: "6.1.0",
                scoutVersion: "0.1.0",
                processesHidden: false
            ),
            cpu: CPUFigures(
                cores: 4,
                use: cpuUser.map { CPUUse(user: $0, system: 0.05, ioWait: 0.01, steal: 0) },
                load: LoadAverages(oneMinute: 1, fiveMinutes: 1, fifteenMinutes: 1)
            ),
            memory: MemoryFigures(
                totalBytes: 8_000_000_000,
                availableBytes: availableBytes,
                cacheBytes: 2_000_000_000,
                swapTotalBytes: 0,
                swapUsedBytes: 0,
                swapping: nil
            ),
            pressure: nil,
            filesystems: filesystems,
            disks: [DiskFigures(name: "vda", activity: nil)],
            networkInterfaces: [NetworkInterfaceFigures(name: "eth0", traffic: nil)],
            processes: ProcessFigures(count: 300, zombies: 0, groups: [
                ProcessGroup(command: "php-fpm", user: "www-data", count: 40, cpuCores: 0.8, ownMemoryBytes: 400_000_000),
            ])
        )
    }

    /// One sample every 10 seconds from `start`, the first at `start`.
    static func run(count: Int, from start: Int64 = start) -> [MetricsSample] {
        (0 ..< count).map { sample(at: start + Int64($0) * 10) }
    }

    private static func filesystem(_ mountPoint: String, available: UInt64) -> FilesystemFigures {
        FilesystemFigures(
            mountPoint: mountPoint,
            device: "/dev/vda1",
            type: "ext4",
            space: FilesystemSpace(
                sizeBytes: 1_000_000_000_000,
                usedBytes: 1_000_000_000_000 - available,
                availableBytes: available,
                inodes: InodeCounts(used: 100_000, free: 900_000)
            )
        )
    }
}
