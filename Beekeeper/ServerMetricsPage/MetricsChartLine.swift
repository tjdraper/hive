import SwiftUI

/// One bucket of a line on a server's chart. Times are seconds since 1970 on the server's clock.
struct MetricsChartPoint {
    let start: Int64
    /// A new run starts after each gap, so the line breaks there instead of joining across it.
    let run: Int
    let average: Double
    /// Nil where it isn't kept, such as for a total, or for a single sample, whose highest is its average.
    let highest: Double?
    let lowest: Double?
    /// Where a stacked area starts: the parts beneath it, together.
    var base: Double = 0
}

/// A figure as one chart draws it: its average, with its highest above it and its lowest below where
/// they're kept, so a spike averaged away still shows.
struct MetricsChartLine: Identifiable {
    enum Style {
        case line
        /// An area on top of the stacked areas before it, such as each part of CPU use.
        case stacked
        /// Dashed, without a band, for a limit or a bound such as the number of cores.
        case outline
    }

    let name: String
    let color: Color
    var style = Style.line
    let points: [MetricsChartPoint]

    var id: String {
        name
    }

    /// The bucket holding `second`, if anything was kept in it.
    func point(at second: Int64, bucketSeconds: Int64) -> MetricsChartPoint? {
        var low = 0
        var high = points.count
        while low < high {
            let middle = (low + high) / 2
            if points[middle].start <= second { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return nil }
        let point = points[low - 1]
        return second < point.start + bucketSeconds ? point : nil
    }

    /// Each part's lines stacked in order, so each starts where the one beneath it ends.
    static func stacked(_ lines: [MetricsChartLine]) -> [MetricsChartLine] {
        var bases: [Int64: Double] = [:]
        return lines.map { line in
            let points = line.points.map { point in
                var stacked = point
                stacked.base = bases[point.start, default: 0]
                bases[point.start] = stacked.base + point.average
                return stacked
            }
            return MetricsChartLine(name: line.name, color: line.color, style: .stacked, points: points)
        }
    }
}
