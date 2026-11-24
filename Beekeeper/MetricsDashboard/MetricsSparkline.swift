import Charts
import HiveKit
import SwiftUI

/// CPU and memory for each minute of the last hour, from 0 to 100%, with a gap where nothing was kept.
struct MetricsSparkline: View {
    let points: [MetricsSparkPoint]
    /// The end of the hour, on the server's clock.
    let end: Date

    private struct Line {
        let name: String
        let color: Color
        let figure: KeyPath<MetricsSparkPoint, Double?>
    }

    private struct Mark: Identifiable {
        let date: Date
        let value: Double
        /// A new run starts after each gap, so the line breaks there instead of joining across it.
        let run: Int

        var id: Date {
            date
        }
    }

    private static let lines = [
        Line(name: "CPU", color: Color(.metricsCPU), figure: \.cpuBusy),
        Line(name: "Memory", color: Color(.metricsMemory), figure: \.memoryUsed),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Chart {
                ForEach(Self.lines, id: \.name) { line in
                    ForEach(marks(line.figure)) { mark in
                        LineMark(
                            x: .value("Time", mark.date),
                            y: .value(line.name, mark.value),
                            series: .value("Series", "\(line.name) \(mark.run)")
                        )
                        .foregroundStyle(line.color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .chartXScale(domain: end.addingTimeInterval(-3_600) ... end)
            .chartYScale(domain: 0 ... 1)
            .chartXAxis(.hidden)
            .chartYAxis {
                // 0 and 100%, faint, so a line near either still shows over it.
                AxisMarks(values: [0, 1]) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                }
            }
            .chartLegend(.hidden)
            .frame(height: 44)
            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The last hour")
        .accessibilityValue(accessibilitySummary)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(Self.lines, id: \.name) { line in
                HStack(spacing: 4) {
                    Capsule()
                        .fill(line.color)
                        .frame(width: 10, height: 3)
                    Text(line.name)
                }
            }
            Spacer(minLength: 0)
            Text("Last hour")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    /// Each minute at its middle, since a point stands for the whole minute.
    private func marks(_ figure: KeyPath<MetricsSparkPoint, Double?>) -> [Mark] {
        var marks: [Mark] = []
        var run = 0
        var previous: Int64?
        for point in points {
            guard let value = point[keyPath: figure] else {
                previous = nil
                continue
            }
            if let previous, point.startsAt - previous > 60 { run += 1 }
            if previous == nil, !marks.isEmpty { run += 1 }
            marks.append(Mark(date: Date(timeIntervalSince1970: TimeInterval(point.startsAt + 30)), value: value, run: run))
            previous = point.startsAt
        }
        return marks
    }

    private var accessibilitySummary: String {
        Self.lines.compactMap { line -> String? in
            guard let highest = points.compactMap({ $0[keyPath: line.figure] }).max() else { return nil }
            return "\(line.name) up to \(highest.formatted(.percent.precision(.fractionLength(0))))"
        }
        .joined(separator: ", ")
    }
}
