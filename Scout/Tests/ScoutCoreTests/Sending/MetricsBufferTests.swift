@testable import ScoutCore
import ScoutProtocol
import Testing

struct MetricsBufferTests {
    @Test("After a day without Hive, the last hour is held whole and the 23 hours before it as minutes, and nothing older")
    func keepsADay() throws {
        // Arrange
        var buffer = MetricsBuffer()
        let samples = TestSamples.run(count: 25 * 360)
        let newest = try #require(samples.last).takenAt

        // Act
        for sample in samples { buffer.add(sample) }

        // Assert
        #expect(buffer.samples.count == 360)
        #expect(buffer.samples.first?.takenAt == newest - 3_590)
        let starts = buffer.minutes.map(\.startsAt)
        #expect(starts.allSatisfy { $0 > newest - 86_400 })
        #expect(zip(starts, starts.dropFirst()).allSatisfy { $1 - $0 == 60 })
        // Every sample of the last day is held, whole or in its minute: 8,640 of them.
        #expect(buffer.minutes.reduce(0) { $0 + $1.sampleCount } + buffer.heldSampleCount == 8_640)
    }

    @Test("A clock set back can't make the buffer hold more than an hour of whole samples")
    func clockSetBack() {
        // Arrange
        var buffer = MetricsBuffer()

        // Act
        for index in 0 ..< 400 { buffer.add(TestSamples.sample(at: TestSamples.start - Int64(index) * 10)) }

        // Assert
        #expect(buffer.samples.count == 360)
    }

    @Test("The newest sample goes first, then minutes and samples oldest first in batches, and a new sample goes ahead of the rest")
    func sendingOrder() throws {
        // Arrange: 400 samples, so the first 40 are folded into minutes.
        var buffer = MetricsBuffer()
        let samples = TestSamples.run(count: 400)
        for sample in samples { buffer.add(sample) }
        let start = TestSamples.start

        // Act, Assert
        #expect(buffer.nextBatch() == .init(samples: [samples[399]], minutes: []))
        buffer.settle(.delivered)

        let minutesBatch = buffer.nextBatch()
        let minutes = try #require(minutesBatch)
        #expect(minutes.samples.isEmpty)
        #expect(minutes.minutes.map(\.startsAt) == [start, start + 60, start + 120, start + 180, start + 240, start + 300])
        buffer.settle(.delivered)

        let firstBatch = buffer.nextBatch()
        let firstSamples = try #require(firstBatch)
        #expect(firstSamples.samples.map(\.takenAt) == (40 ..< 100).map { start + Int64($0) * 10 })
        buffer.settle(.delivered)

        let newer = TestSamples.sample(at: start + 4_000)
        buffer.add(newer)
        #expect(buffer.nextBatch()?.samples == [newer])
        buffer.settle(.delivered)

        var rest: [Int64] = []
        while let batch = buffer.nextBatch() {
            #expect(batch.samples.count <= MetricsReport.largestSampleCount)
            rest += batch.samples.map(\.takenAt)
            buffer.settle(.delivered)
        }
        #expect(rest == (100 ..< 399).map { start + Int64($0) * 10 })
    }

    @Test("A returned batch is offered again, a refused one dropped, and samples are added while one is out")
    func settling() {
        // Arrange
        var buffer = MetricsBuffer()
        let samples = TestSamples.run(count: 3)
        buffer.add(samples[0])
        buffer.add(samples[1])

        // Act, Assert
        let first = buffer.nextBatch()
        #expect(first?.samples == [samples[1]])
        #expect(buffer.nextBatch() == nil)
        buffer.add(samples[2])
        #expect(buffer.heldSampleCount == 3)

        buffer.settle(.returned)
        #expect(buffer.nextBatch()?.samples == [samples[2]])
        buffer.settle(.refused)
        #expect(buffer.nextBatch()?.samples == [samples[0], samples[1]])
        buffer.settle(.delivered)
        #expect(buffer.nextBatch() == nil)
        #expect(buffer.heldSampleCount == 0)
    }
}

struct MinuteRollupTests {
    @Test("A minute keeps each figure's average and highest, and the lowest where it matters, from the samples that have it")
    func rollup() throws {
        // Arrange: no CPU use in the first sample, as after Scout starts, and /data only in the last two.
        let start = TestSamples.start
        let users: [Double?] = [nil, 0.2, 0.4, 0.6, 0.8, 1.0]
        let gigabyte: UInt64 = 1_000_000_000
        let samples: [MetricsSample] = (0 ..< 6).map { (index: Int) -> MetricsSample in
            let offset = UInt64(index)
            return TestSamples.sample(
                at: start + Int64(index) * 10,
                cpuUser: users[index],
                availableBytes: (6 - offset) * gigabyte,
                rootAvailableBytes: (10 + offset) * gigabyte,
                dataDisk: index >= 4
            )
        }

        // Act
        let minute = MinuteRollup.minute(startingAt: start, of: samples)

        // Assert
        #expect(minute.startsAt == start)
        #expect(minute.sampleCount == 6)
        let averageUser = try #require(minute.average.cpu?.use?.user)
        #expect(abs(averageUser - 0.6) < 1e-9)
        #expect(minute.highest.cpu?.use?.user == 1.0)
        #expect(minute.average.memory?.availableBytes == 3_500_000_000)
        #expect(minute.highest.memory?.availableBytes == 6 * gigabyte)
        #expect(minute.lowest.memoryAvailableBytes == 1 * gigabyte)
        #expect(minute.average.filesystems.map(\.mountPoint) == ["/", "/data"])
        #expect(minute.average.filesystems.first?.space?.availableBytes == 12_500_000_000)
        #expect(minute.lowest.filesystems.map(\.availableBytes) == [10 * gigabyte, 900 * gigabyte])
    }
}
