import Foundation
@testable import HiveCore
import Testing

struct FigureHistoryTests {
    /// A sample every 10 seconds from `start` up to `end`, inclusive, each `value`.
    private func samples(from start: Int64, to end: Int64, value: Double) -> [(at: Int64, value: Double)] {
        stride(from: start, through: end, by: 10).map { ($0, value) }
    }

    @Test("An average needs samples back to the start of its duration, and a gap of over a minute leaves none")
    func averageNeedsCover() {
        // Arrange
        let full = FigureHistory(samples: samples(from: 10, to: 600, value: 1))
        let lateStart = FigureHistory(samples: samples(from: 20, to: 600, value: 1))
        let gap = FigureHistory(samples: samples(from: 10, to: 200, value: 1) + samples(from: 270, to: 600, value: 1))
        let missedOne = FigureHistory(samples: samples(from: 10, to: 200, value: 1) + samples(from: 220, to: 600, value: 3))

        // Act
        let averages = [full, lateStart, gap, missedOne].map { $0.average(over: 600, upTo: 600) }

        // Assert
        #expect(averages[0] == 1)
        #expect(averages[1] == nil)
        #expect(averages[2] == nil)
        #expect(averages[3].map { abs($0 - (20 + 39 * 3) / 59.0) < 1e-9 } == true)
    }

    @Test("Cleared needs the whole period within the limit, judged by each moment's average, and the history to reach back")
    func cleared() {
        // Arrange
        let isOver: (Double) -> Bool = { $0 > 0.9 }
        let busyThenIdle = FigureHistory(samples: samples(from: 10, to: 900, value: 1) + samples(from: 910, to: 6_000, value: 0))
        let short = FigureHistory(samples: samples(from: 3_000, to: 6_000, value: 0))

        // Act
        let early = busyThenIdle.hasCleared(isOver, over: 900, for: 3_600, upTo: 4_000)
        let later = busyThenIdle.hasCleared(isOver, over: 900, for: 3_600, upTo: 6_000)
        let tooShort = short.hasCleared(isOver, over: 900, for: 3_600, upTo: 6_000)

        // Assert
        #expect(!early)
        #expect(later)
        #expect(!tooShort)
    }
}
