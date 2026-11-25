import Foundation
@testable import HiveCore
import HiveKit
import ScoutProtocol
import Testing

struct MetricsSeriesTests {
    private let database: MetricsDatabase
    private let store: MetricsStore
    private let serverID = UUID()
    private let start = TestMetrics.start
    private let day: Int64 = 86_400

    init() throws {
        database = try MetricsDatabase.inMemory()
        store = MetricsStore(database: database)
    }

    /// Kept as a Scout sends them, with its clock and Hive's agreeing.
    private func keep(_ samples: [MetricsSample], minutes: [MetricsMinute] = []) throws {
        let report = TestMetrics.report(samples, minutes: minutes)
        #expect(try store.keep(report, forServer: serverID, at: TestMetrics.date(report.sentAt)) != .refused(.tooOld))
    }

    private func series(_ range: Range<Int64>, now: Int64, _ figures: [MetricsFigure]) throws -> MetricsSeries {
        try MetricsSeriesReader(database: database, now: { TestMetrics.date(now) })
            .series(ofServer: serverID, over: range, figures: figures)
    }

    private func sample(at time: Int64, cpu: Double, available: UInt64 = 4_000_000_000) -> MetricsSample {
        TestMetrics.sample(at: time, cpuUser: cpu, availableBytes: available)
    }

    @Test(
        "A range comes back in about 600 buckets, never finer than the finest resolution still kept at its start",
        arguments: zip(
            [
                // An hour, a day, a week, 30 days and a year, ending now.
                (3_600, 0), (86_400, 0), (7 * 86_400, 0), (30 * 86_400, 0), (365 * 86_400, 0),
                // An hour two days ago has only minutes left, and ten days ago only hours.
                (3_600, 2 * 86_400), (3_600, 10 * 86_400),
                // A week asked for a few seconds before Hive read it still has its minutes, and a
                // week and two hours ago doesn't.
                (7 * 86_400, 5), (3_600, 7 * 86_400 + 2 * 3_600),
            ] as [(Int64, Int64)],
            [10, 180, 1_200, 7_200, 86_400, 60, 3_600, 1_200, 3_600] as [Int64]
        )
    )
    func bucketSizes(range: (length: Int64, endsBeforeNow: Int64), expected: Int64) {
        // Arrange
        let now = start + 400 * day
        let end = now - range.endsBeforeNow

        // Act
        let bucketSeconds = MetricsSeriesReader.bucketSeconds(for: end - range.length ..< end, serverNow: now)

        // Assert
        #expect(bucketSeconds == expected)
    }

    @Test("An hour's range has a bucket for each 10-second sample, and none for a gap, even where minutes are kept")
    func tenSecondBucketsWithGap() throws {
        // Arrange
        let values = [(0, 0.1), (10, 0.2), (20, 0.6), (120, 0.3), (130, 0.5)] as [(Int64, Double)]
        try keep(values.map { sample(at: start + $0.0, cpu: $0.1) })

        // Act
        let series = try series(start ..< start + 3_600, now: start + 3_600, [.cpuUser, .memoryAvailable])

        // Assert
        #expect(series.bucketSeconds == 10)
        let server = try #require(series.subjects.only)
        #expect(server.kind == .server && server.name == nil)
        #expect(server.bucketStarts == values.map { start + $0.0 })
        let cpu = try #require(server.figures.first { $0.figure == .cpuUser })
        #expect(cpu.average == values.map(\.1))
        #expect(cpu.highest == values.map(\.1))
        #expect(cpu.lowest == nil)
        #expect(try #require(server.figures.first { $0.figure == .memoryAvailable }).lowest?.count == values.count)
    }

    @Test("A larger bucket holds the average and highest of its samples, and the lowest where it's kept")
    func largerBuckets() throws {
        // Arrange: one busy sample among eighteen in the first 3 minutes, then one in the next.
        var samples = (0 ..< 18).map { sample(at: start + Int64($0) * 10, cpu: 0.1) }
        samples[5] = sample(at: start + 50, cpu: 0.9, available: 1_000_000_000)
        samples.append(sample(at: start + 180, cpu: 0.3))
        try keep(samples)

        // Act
        let series = try series(start ..< start + day, now: start + day, [.cpuUser, .memoryAvailable])

        // Assert
        #expect(series.bucketSeconds == 180)
        let server = try #require(series.subjects.only)
        #expect(server.bucketStarts == [start, start + 180])
        let cpu = try #require(server.figures.first { $0.figure == .cpuUser })
        #expect(TestMetrics.isClose(try #require(cpu.average[0]), 2.6 / 18))
        #expect(TestMetrics.isClose(try #require(cpu.average[1]), 0.3))
        #expect(cpu.highest == [0.9, 0.3])
        let memory = try #require(server.figures.first { $0.figure == .memoryAvailable })
        #expect(memory.lowest == [1_000_000_000, 4_000_000_000])
        #expect(memory.highest == [4_000_000_000, 4_000_000_000])
    }

    @Test("A minute a Scout held while Hive was unreachable fills each 10-second bucket it covers")
    func backlogMinuteFillsBuckets() throws {
        // Arrange
        let minute = TestMetrics.minute(at: start + 60, average: 0.5, highest: 0.9, lowestAvailable: 1_000_000_000)
        try keep([sample(at: start, cpu: 0.2), sample(at: start + 10, cpu: 0.2)], minutes: [minute])

        // Act
        let series = try series(start ..< start + 3_600, now: start + 3_600, [.cpuUser, .memoryAvailable])

        // Assert
        let server = try #require(series.subjects.only)
        #expect(server.bucketStarts == [start, start + 10] + stride(from: start + 60, to: start + 120, by: 10))
        let cpu = try #require(server.figures.first { $0.figure == .cpuUser })
        #expect(cpu.average == [0.2, 0.2] + Array(repeating: 0.5, count: 6))
        #expect(cpu.highest == [0.2, 0.2] + Array(repeating: 0.9, count: 6))
        let memory = try #require(server.figures.first { $0.figure == .memoryAvailable })
        #expect(memory.lowest?.suffix(6).allSatisfy { $0 == 1_000_000_000 } == true)
    }

    @Test("A range starting partway through an hour reads its samples, not the whole hour's figures")
    func rangeStartingMidHour() throws {
        // Arrange: a quiet first half hour, then a busy one, a report a minute's samples as Scout sends.
        for minute in 0 ..< 60 {
            try keep((0 ..< 6).map { sample(at: start + Int64(minute * 60 + $0 * 10), cpu: minute < 30 ? 0.1 : 0.5) })
        }

        // Act
        let series = try series(start + 1_800 ..< start + 3_600, now: start + 3_600, [.cpuUser])

        // Assert
        let server = try #require(series.subjects.only)
        #expect(server.bucketStarts == Array(stride(from: start + 1_800, to: start + 3_600, by: 10)))
        #expect(try #require(server.figures.only).average.allSatisfy { $0 == 0.5 })
    }

    @Test("A range crossing from pruned periods to recent ones reads each from the resolution still kept")
    func crossesResolutions() throws {
        // Arrange
        try keep([sample(at: start, cpu: 0.2), sample(at: start + 10, cpu: 0.4)])
        let recent = start + 8 * day
        try keep([sample(at: recent, cpu: 0.7)])
        let now = recent + 10
        let known: Set<UUID> = [serverID]
        MetricsUpkeep(database: database, knownServerIDs: { known }, now: { TestMetrics.date(now) }).runOnce()
        #expect(try database.startTimes("serverTenSeconds") == [recent])
        #expect(try database.startTimes("serverMinute") == [recent])

        // Act
        let series = try series(start ..< now, now: now, [.cpuUser])

        // Assert
        #expect(series.bucketSeconds == 3_600)
        let server = try #require(series.subjects.only)
        #expect(server.bucketStarts == [start, recent])
        let cpu = try #require(server.figures.only)
        #expect(TestMetrics.isClose(try #require(cpu.average[0]), 0.3))
        #expect(cpu.average[1] == 0.7)
        #expect(cpu.highest == [0.4, 0.7])
    }

    @Test("Figures kept by name come back for each name, and only the subjects asked for")
    func namedSubjects() throws {
        // Arrange
        var first = sample(at: start, cpu: 0.1)
        first.filesystems = [TestMetrics.filesystem("/var", available: 20), TestMetrics.filesystem("/", available: 10)]
        try keep([first])

        // Act
        let series = try series(start ..< start + 3_600, now: start + 3_600, [.filesystemAvailable])

        // Assert
        #expect(series.subjects.map(\.kind) == [.filesystem, .filesystem])
        #expect(series.subjects.map(\.name) == ["/", "/var"])
        #expect(series.subjects.map { $0.figures.only?.lowest } == [[10], [20]])
    }

    @Test("A server with nothing kept has no subjects")
    func unknownServer() throws {
        // Arrange
        try keep([sample(at: start - 60, cpu: 0.5)])

        // Act
        let series = try MetricsSeriesReader(database: database, now: { TestMetrics.date(start) })
            .series(ofServer: UUID(), over: start - 3_600 ..< start, figures: [.cpuUser])

        // Assert
        #expect(series.subjects.isEmpty)
    }
}
