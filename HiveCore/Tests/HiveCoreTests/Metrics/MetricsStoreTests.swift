import Foundation
import GRDB
@testable import HiveCore
import ScoutProtocol
import Testing

struct MetricsStoreTests {
    private let database: MetricsDatabase
    private let store: MetricsStore
    private let serverID = UUID()
    private let start = TestMetrics.start

    init() throws {
        database = try MetricsDatabase.inMemory()
        store = MetricsStore(database: database)
    }

    @discardableResult
    private func keep(_ report: MetricsReport, at now: Int64? = nil) throws -> MetricsKeepOutcome {
        try store.keep(report, forServer: serverID, at: TestMetrics.date(now ?? start + 3_600))
    }

    /// Three samples in the first minute, none in the second, and two in the third.
    private var series: [MetricsSample] {
        [
            TestMetrics.sample(at: start, cpuUser: 0.1, availableBytes: 4_000_000_000),
            TestMetrics.sample(at: start + 10, cpuUser: 0.2, availableBytes: 3_000_000_000),
            TestMetrics.sample(at: start + 20, cpuUser: 0.6, availableBytes: 5_000_000_000),
            TestMetrics.sample(at: start + 120, cpuUser: 0.3),
            TestMetrics.sample(at: start + 130, cpuUser: 0.5),
        ]
    }

    @Test("Each minute and hour keeps its samples' average and highest, the lowest where it matters, and nothing for a gap")
    func rollsUpWithGap() throws {
        // Act
        let outcome = try keep(TestMetrics.report(series))

        // Assert
        #expect(outcome == .kept(samples: 5, minutes: 0))
        let minutes = try database.serverRows(.minute)
        #expect(minutes.keys.sorted() == [start, start + 120])
        let first = try #require(minutes[start])
        #expect(first["sampleCount"] as Int == 3)
        #expect(TestMetrics.isClose(first["cpuUser"], 0.3))
        #expect(TestMetrics.isClose(first["cpuUserHighest"], 0.6))
        #expect(first["memoryAvailable"] as Int64 == 4_000_000_000)
        #expect(first["memoryAvailableHighest"] as Int64 == 5_000_000_000)
        #expect(first["memoryAvailableLowest"] as Int64 == 3_000_000_000)
        #expect(first["memoryTotal"] as Int64 == 8_000_000_000)
        #expect(TestMetrics.isClose(try #require(minutes[start + 120])["cpuUser"], 0.4))

        // Weighted by each minute's samples: the minutes' averages would give 0.35.
        let hour = try #require(try database.serverRows(.hour)[start])
        #expect(hour["sampleCount"] as Int == 5)
        #expect(TestMetrics.isClose(hour["cpuUser"], 0.34))
        #expect(TestMetrics.isClose(hour["cpuUserHighest"], 0.6))
        #expect(hour["memoryAvailableLowest"] as Int64 == 3_000_000_000)
    }

    @Test("A late sample landing in a closed minute makes that minute and its hour again")
    func lateBatch() throws {
        // Arrange
        try keep(TestMetrics.report(series))

        // Act
        try keep(TestMetrics.report([TestMetrics.sample(at: start + 30, cpuUser: 1)], sentAt: start + 3_600))

        // Assert
        let minute = try #require(try database.serverRows(.minute)[start])
        #expect(minute["sampleCount"] as Int == 4)
        #expect(TestMetrics.isClose(minute["cpuUser"], 0.475))
        #expect(TestMetrics.isClose(minute["cpuUserHighest"], 1))
        let hour = try #require(try database.serverRows(.hour)[start])
        #expect(hour["sampleCount"] as Int == 6)
        #expect(TestMetrics.isClose(hour["cpuUser"], 0.45))
    }

    @Test("A minute from a backlog fills its minute and feeds the hour, without replacing one made from more samples")
    func backlogMinutes() throws {
        // Arrange
        try keep(TestMetrics.report(series))
        let gap = TestMetrics.minute(at: start + 60, sampleCount: 6, average: 0.5, highest: 0.9, lowestAvailable: 1_000_000_000)
        let fewer = TestMetrics.minute(at: start, sampleCount: 2, average: 0.9, highest: 0.9, lowestAvailable: 1)

        // Act
        let outcome = try keep(TestMetrics.report(minutes: [gap, fewer]))
        try keep(TestMetrics.report(minutes: [gap]))

        // Assert
        #expect(outcome == .kept(samples: 0, minutes: 2))
        let minutes = try database.serverRows(.minute)
        let filled = try #require(minutes[start + 60])
        #expect(filled["sampleCount"] as Int == 6)
        #expect(TestMetrics.isClose(filled["cpuUser"], 0.5))
        #expect(TestMetrics.isClose(filled["cpuUserHighest"], 0.9))
        #expect(filled["memoryAvailableHighest"] as Int64 == 5_000_000_000)
        #expect(filled["memoryAvailableLowest"] as Int64 == 1_000_000_000)
        #expect(try #require(minutes[start])["sampleCount"] as Int == 3)
        let filesystemLowest = try database.writer.read {
            try Int64.fetchOne($0, sql: "SELECT availableLowest FROM filesystemMinute WHERE startsAt = ?", arguments: [start + 60])
        }
        #expect(filesystemLowest == 40_000_000_000)

        let hour = try #require(try database.serverRows(.hour)[start])
        #expect(hour["sampleCount"] as Int == 11)
        #expect(TestMetrics.isClose(hour["cpuUser"], 4.7 / 11))
        #expect(TestMetrics.isClose(hour["cpuUserHighest"], 0.9))
        #expect(hour["memoryAvailableLowest"] as Int64 == 1_000_000_000)
    }

    @Test("A batch sent again, and a sample repeated within one, are each kept once")
    func duplicates() throws {
        // Arrange
        let report = TestMetrics.report([
            TestMetrics.sample(at: start, cpuUser: 0.1),
            TestMetrics.sample(at: start, cpuUser: 0.9),
            TestMetrics.sample(at: start + 10, cpuUser: 0.3),
        ])

        // Act
        try keep(report)
        try keep(report)

        // Assert
        #expect(try database.cpuUser(ofServer: serverID) == [0.1, 0.3])
        #expect(try #require(try database.serverRows(.minute)[start])["sampleCount"] as Int == 2)
        #expect(try #require(try database.serverRows(.hour)[start])["sampleCount"] as Int == 2)
        #expect(try database.count("filesystemTenSeconds") == 2)
        #expect(try database.count("processTenSeconds") == 2)
    }

    @Test("Pruning keeps exactly each resolution's period, and each hour's process groups for two weeks")
    func pruning() throws {
        // Arrange
        let day: Int64 = 86_400
        let now = start + 400 * day
        let times = [
            now - day - 10, now - day,
            now - 7 * day - 60, now - 7 * day,
            now - 365 * day - 3_600, now - 365 * day,
        ]
        for time in times.reversed() {
            let filesystems = time == times[4] ? ["/", "/old"] : ["/"]
            try keep(TestMetrics.report([TestMetrics.sample(at: time, filesystems: filesystems)]), at: time)
        }
        let upkeep = MetricsUpkeep(database: database, knownServerIDs: { [serverID] in [serverID] }, now: { TestMetrics.date(now) })

        // Act
        upkeep.runOnce()

        // Assert
        #expect(try database.serverRows(.tenSeconds).keys.sorted() == [now - day])
        #expect(try database.serverRows(.minute).keys.sorted() == [now - 7 * day, now - day - 60, now - day])
        let hours = [now - 365 * day, now - 7 * day - 3_600, now - 7 * day, now - day - 3_600, now - day]
        #expect(try database.serverRows(.hour).keys.sorted() == hours)
        #expect(try database.startTimes("processTenSeconds") == [now - day])
        #expect(try database.startTimes("processHour") == [now - 7 * day - 3_600, now - 7 * day, now - day - 3_600, now - day])
        let names = try database.writer.read { try String.fetchAll($0, sql: "SELECT name FROM metricsName WHERE kind = 'filesystem'") }
        #expect(names == ["/"])
    }

    @Test("The hourly pass removes what's kept for servers no longer in Hive")
    func removesUnknownServers() throws {
        // Arrange
        try keep(TestMetrics.report(series))
        let upkeep = MetricsUpkeep(database: database, knownServerIDs: { [] }, now: { TestMetrics.date(TestMetrics.start + 3_600) })

        // Act
        upkeep.runOnce()

        // Assert
        #expect(try database.count("metricsServer") == 0)
        #expect(try database.count("metricsName") == 0)
        #expect(try database.count("serverTenSeconds") == 0)
        #expect(try database.count("processTenSeconds") == 0)
    }

    @Test("An hour keeps its top process groups by CPU and by memory, counting a group missing from a sample as nothing")
    func hourlyProcessGroups() {
        // Arrange
        let groups = (0 ..< 12).map { index in
            ProcessGroup(command: "c\(index)", user: "u", count: 1, cpuCores: Double(index), ownMemoryBytes: UInt64(index) * 1_000)
        }
        let busyOnce = ProcessGroup(command: "cron", user: "root", count: 3, cpuCores: 30, ownMemoryBytes: 0)

        // Act
        let hourly = ProcessGroupStorage.hourly(of: [groups + [busyOnce], groups])

        // Assert
        let kept = Set(hourly.map(\.command))
        #expect(kept == Set(["cron"] + (2 ..< 12).map { "c\($0)" }))
        let cron = hourly.first { $0.command == "cron" }
        #expect(cron?.averageCPUCores == 15)
        #expect(cron?.highestCPUCores == 30)
        #expect(cron?.highestCount == 3)
    }

    @Test("The migrations make each figure table with the columns `MetricsTables` writes")
    func schemaMatchesTables() throws {
        for table in MetricsTables.all {
            for resolution in MetricsResolution.allCases {
                // Arrange
                let rollupColumns = resolution == .tenSeconds ? [] : ["sampleCount"]
                let expected = [table.keyColumn, "startsAt"] + rollupColumns + table.figureColumns(resolution)

                // Act
                let columns = try database.writer.read { try $0.columns(in: table.table(resolution)) }

                // Assert
                #expect(columns.map(\.name) == expected, "\(table.table(resolution))")
                let wholeColumns = Set(table.columns.filter(\.isWhole).flatMap { [$0.name, $0.highest, $0.lowest].compactMap(\.self) })
                for column in columns where table.figureColumns(resolution).contains(column.name) {
                    #expect(column.type == (wholeColumns.contains(column.name) ? "INTEGER" : "DOUBLE"), "\(column.name)")
                }
            }
        }
    }

    @Test("The database is opened in its own folder, left out of Time Machine, and opened again with what it kept")
    func opensExcludedFromBackup() throws {
        // Arrange
        let temporary = try TemporaryDirectory()
        let first = try MetricsDatabase.open(in: temporary.url)
        _ = try MetricsStore(database: first).keep(TestMetrics.report(series), forServer: serverID, at: TestMetrics.date(start + 3_600))

        // Act
        let again = try MetricsDatabase.open(in: temporary.url)

        // Assert
        let folder = temporary.url.appending(path: MetricsDatabase.folderName, directoryHint: .isDirectory)
        #expect(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: MetricsDatabase.fileName).path(percentEncoded: false)))
        #expect(try again.count("serverTenSeconds") == 5)
    }
}
