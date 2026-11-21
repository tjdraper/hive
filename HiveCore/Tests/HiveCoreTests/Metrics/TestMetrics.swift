import Foundation
import GRDB
@testable import HiveCore
import ScoutProtocol

/// Samples, minutes and reports with the figures a test sets and the rest plausible.
enum TestMetrics {
    /// On an hour mark, and the fixtures' clock.
    static let start: Int64 = 1_800_000_000

    static func date(_ seconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    static func sample(
        at takenAt: Int64,
        cpuUser: Double = 0.25,
        availableBytes: UInt64 = 4_000_000_000,
        filesystems: [String] = ["/"],
        processGroups: [ProcessGroup]? = nil
    ) -> MetricsSample {
        MetricsSample(
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
                use: CPUUse(user: cpuUser, system: 0.05, ioWait: 0.01, steal: 0),
                load: LoadAverages(oneMinute: 1, fiveMinutes: 1, fifteenMinutes: 1)
            ),
            memory: memory(available: availableBytes),
            pressure: nil,
            filesystems: filesystems.map { filesystem($0, available: 50_000_000_000) },
            disks: [DiskFigures(name: "vda", activity: nil)],
            networkInterfaces: [NetworkInterfaceFigures(name: "eth0", traffic: nil)],
            processes: ProcessFigures(count: 300, zombies: 0, groups: processGroups ?? [
                ProcessGroup(command: "php-fpm", user: "www-data", count: 40, cpuCores: 0.8, ownMemoryBytes: 400_000_000),
            ])
        )
    }

    /// A minute as Scout folds one: `average` and `highest` CPU, and the lowest available memory.
    static func minute(
        at startsAt: Int64,
        sampleCount: Int = 6,
        average: Double,
        highest: Double,
        lowestAvailable: UInt64
    ) -> MetricsMinute {
        func figures(_ cpuUser: Double, available: UInt64) -> MinuteFigures {
            MinuteFigures(
                cpu: CPUFigures(cores: 4, use: CPUUse(user: cpuUser, system: 0, ioWait: 0, steal: 0), load: nil),
                memory: memory(available: available),
                pressure: nil,
                filesystems: [filesystem("/", available: 50_000_000_000)],
                disks: [],
                networkInterfaces: []
            )
        }
        return MetricsMinute(
            startsAt: startsAt,
            sampleCount: sampleCount,
            average: figures(average, available: 4_000_000_000),
            highest: figures(highest, available: 5_000_000_000),
            lowest: MinuteLows(memoryAvailableBytes: lowestAvailable, filesystems: [
                FilesystemLows(mountPoint: "/", availableBytes: 40_000_000_000, inodesFree: nil),
            ])
        )
    }

    static func report(
        _ samples: [MetricsSample] = [],
        minutes: [MetricsMinute] = [],
        sentAt: Int64? = nil,
        protocolVersion: Int = ScoutProtocolVersion.current
    ) -> MetricsReport {
        let latest = (samples.map(\.takenAt) + minutes.map(\.startsAt)).max() ?? start
        return MetricsReport(protocolVersion: protocolVersion, sentAt: sentAt ?? latest, samples: samples, minutes: minutes)
    }

    static func memory(available: UInt64) -> MemoryFigures {
        MemoryFigures(
            totalBytes: 8_000_000_000,
            availableBytes: available,
            cacheBytes: 2_000_000_000,
            swapTotalBytes: 0,
            swapUsedBytes: 0,
            swapping: nil
        )
    }

    static func filesystem(_ mountPoint: String, available: UInt64) -> FilesystemFigures {
        FilesystemFigures(
            mountPoint: mountPoint,
            device: "/dev/vda1",
            type: "ext4",
            space: FilesystemSpace(
                sizeBytes: 100_000_000_000,
                usedBytes: 100_000_000_000 - available,
                availableBytes: available,
                inodes: InodeCounts(used: 100_000, free: 900_000)
            )
        )
    }
}

extension TestMetrics {
    static func isClose(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 1e-9
    }
}

extension MetricsDatabase {
    /// The CPU user share of each of the server's 10-second rows, oldest first.
    func cpuUser(ofServer serverID: UUID) throws -> [Double] {
        try writer.read { database in
            try Double.fetchAll(database, sql: """
            SELECT cpuUser FROM serverTenSeconds
            JOIN metricsServer ON metricsServer.id = serverTenSeconds.serverKey
            WHERE metricsServer.serverID = ? ORDER BY startsAt
            """, arguments: [serverID])
        }
    }

    /// The server's own figures at a resolution, by start time.
    func serverRows(_ resolution: MetricsResolution) throws -> [Int64: Row] {
        try writer.read { database in
            let rows = try Row.fetchAll(database, sql: "SELECT * FROM \(MetricsTables.server.table(resolution)) ORDER BY startsAt")
            return Dictionary(uniqueKeysWithValues: rows.map { row -> (Int64, Row) in (row["startsAt"], row) })
        }
    }

    /// Each start time in the table once, oldest first.
    func startTimes(_ table: String) throws -> [Int64] {
        try writer.read { try Int64.fetchAll($0, sql: "SELECT DISTINCT startsAt FROM \(table) ORDER BY startsAt") }
    }

    func count(_ table: String) throws -> Int {
        try writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") ?? 0 }
    }
}
