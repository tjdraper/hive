import Foundation
@testable import HiveCore
import HiveKit
import ScoutProtocol
import Testing

struct FilesystemForecastTests {
    private let start = TestMetrics.start
    private let gigabyte: UInt64 = 1_000_000_000

    @Test("A growing filesystem fills at its week's rate, and a steady, shrinking or new one has no date")
    func growingSteadyShrinkingAndNew() throws {
        // Arrange: two days of hourly samples. /grow loses 1 GB an hour and has 3 GB left at the
        // newest; /new appears only for the last three hours.
        let database = try MetricsDatabase.inMemory()
        let store = MetricsStore(database: database)
        let serverID = UUID()
        let hours: Int64 = 48
        for hour in 0 ..< hours {
            var sample = TestMetrics.sample(at: start + hour * 3_600)
            sample.filesystems = [
                TestMetrics.filesystem("/grow", available: 50 * gigabyte - UInt64(hour) * gigabyte),
                TestMetrics.filesystem("/steady", available: 50 * gigabyte),
                TestMetrics.filesystem("/shrink", available: 10 * gigabyte + UInt64(hour) * gigabyte / 10),
            ]
            if hour >= hours - 3 { sample.filesystems.append(TestMetrics.filesystem("/new", available: gigabyte)) }
            _ = try store.keep(TestMetrics.report([sample]), forServer: serverID, at: TestMetrics.date(sample.takenAt))
        }

        // Act
        let forecasts = try FilesystemForecaster(database: database).forecasts(ofServer: serverID)

        // Assert
        let byName = Dictionary(uniqueKeysWithValues: forecasts.map { ($0.mountPoint, $0) })
        #expect(forecasts.map(\.mountPoint) == ["/grow", "/new", "/shrink", "/steady"])
        let grow = try #require(byName["/grow"])
        #expect(abs(try #require(grow.growthBytesPerDay) - 24e9) < 1)
        let newest = start + (hours - 1) * 3_600
        #expect(abs(try #require(grow.fillsAt) - (newest + 3 * 3_600)) <= 1)
        let steady = try #require(byName["/steady"])
        #expect(abs(try #require(steady.growthBytesPerDay)) < 1)
        #expect(steady.fillsAt == nil)
        let shrink = try #require(byName["/shrink"])
        #expect(abs(try #require(shrink.growthBytesPerDay) + 2.4e9) < 1)
        #expect(shrink.fillsAt == nil)
        #expect(byName["/new"] == FilesystemForecast(mountPoint: "/new", growthBytesPerDay: nil, fillsAt: nil))
    }

    @Test("Only the last week counts, so a filesystem that filled fast before it and is steady since has no date")
    func onlyTheLastWeek() throws {
        // Arrange: ten days, falling 1 GB an hour for the first three and steady since.
        let database = try MetricsDatabase.inMemory()
        let store = MetricsStore(database: database)
        let serverID = UUID()
        for hour in 0 ..< Int64(10 * 24) {
            var sample = TestMetrics.sample(at: start + hour * 3_600)
            let available = hour < 3 * 24 ? 100 - UInt64(hour) : 100 - 3 * 24
            sample.filesystems = [TestMetrics.filesystem("/", available: available * gigabyte)]
            _ = try store.keep(TestMetrics.report([sample]), forServer: serverID, at: TestMetrics.date(sample.takenAt))
        }

        // Act
        let forecast = try #require(try FilesystemForecaster(database: database).forecasts(ofServer: serverID).only)

        // Assert
        #expect(abs(try #require(forecast.growthBytesPerDay)) < 1)
        #expect(forecast.fillsAt == nil)
    }

    @Test("A filesystem that fills only after a year has its rate but no date")
    func beyondAYear() {
        // Arrange: 1 MB an hour with 1 TB left.
        let hours = (0 ..< 24).map { (startsAt: start + Int64($0) * 3_600, available: 1e12 - Double($0) * 1e6) }

        // Act
        let forecast = FilesystemForecaster.forecast("/", hours: hours)

        // Assert
        #expect(abs((forecast.growthBytesPerDay ?? 0) - 24e6) < 1e-3)
        #expect(forecast.fillsAt == nil)
    }
}
