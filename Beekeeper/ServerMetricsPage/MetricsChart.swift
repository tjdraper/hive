import Charts
import HiveKit
import SwiftUI

/// How a chart's figures read.
enum MetricsValueFormat {
    case share
    case bytes
    case bytesPerSecond
    case load
    case perSecond
    case count

    func text(_ value: Double) -> String {
        if value == 0 { return "0" }
        return switch self {
        case .share:
            value.formatted(.percent.precision(.fractionLength(value > 0 && value < 0.01 ? 1 : 0)))
        case .bytes:
            Int64(value.rounded()).formatted(.byteCount(style: .memory))
        case .bytesPerSecond:
            "\(Int64(value.rounded()).formatted(.byteCount(style: .memory)))/s"
        case .load:
            value.formatted(.number.precision(.fractionLength(0 ... 2)))
        case .perSecond:
            "\(value.formatted(.number.precision(.fractionLength(0 ... 1))))/s"
        case .count:
            value.formatted(.number.precision(.fractionLength(0)))
        }
    }

    /// Bytes step in whole binary units, such as 0, 2, 4 and 6 GB, which the automatic ticks of a
    /// decimal axis don't. Nil leaves the rest to the chart.
    func ticks(upTo upper: Double) -> [Double]? {
        guard self == .bytes || self == .bytesPerSecond, upper > 0 else { return nil }
        let unit = [1_099_511_627_776.0, 1_073_741_824, 1_048_576, 1_024, 1].first { upper >= $0 } ?? 1
        let scaled = upper / unit
        let step = [1.0, 2, 5, 10, 20, 50, 100, 200, 500, 1_000].first { scaled / $0 <= 5 } ?? 1_000
        return stride(from: 0, through: scaled, by: step).map { $0 * unit }
    }
}

/// What every chart on a server's page shares: the range on one time axis, its buckets and the backup
/// runs marked across them.
struct MetricsTimeline {
    let range: Range<Int64>
    private(set) var bucketSeconds: Int64
    let backupRuns: [BackupRunMark]

    init(history: ServerHistory) {
        range = history.range
        bucketSeconds = history.bucketSeconds
        backupRuns = history.backupRuns
    }

    /// The same range in other buckets, for figures Hive keeps at their own resolutions, such as
    /// containers', which are kept by the hour after a day.
    func with(bucketSeconds: Int64) -> MetricsTimeline {
        var timeline = self
        timeline.bucketSeconds = bucketSeconds
        return timeline
    }

    var domain: ClosedRange<Date> {
        Self.date(range.lowerBound) ... Self.date(range.upperBound)
    }

    /// Seconds since 1970 on the server's clock, as the charts' dates stand for them.
    static func date(_ second: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(second))
    }

    static func second(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.down))
    }

    /// Each bucket at its middle, since a point stands for the whole bucket.
    func middle(of point: MetricsChartPoint) -> Date {
        Self.date(point.start).addingTimeInterval(TimeInterval(bucketSeconds) / 2)
    }

    func time(_ date: Date) -> String {
        if range.count > 86_400 {
            date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        } else {
            date.formatted(.dateTime.hour().minute().second())
        }
    }

    func backupRun(at date: Date) -> BackupRunMark? {
        let second = Self.second(date)
        return backupRuns.last { $0.startedAt <= second && second < end(of: $0) }
    }

    /// A run shorter than a bucket is drawn a bucket wide, so it still shows on a long range.
    func end(of run: BackupRunMark) -> Int64 {
        max(run.finishedAt ?? range.upperBound, run.startedAt + bucketSeconds)
    }
}

/// One of a server's charts: a title, each line's figure at the moment shown, and the lines over the
/// page's range, with backup runs shaded behind them.
///
/// Only the legend and the overlay read the moment, so moving the pointer redraws those and leaves the
/// marks alone.
struct MetricsChart: View, Identifiable {
    #if os(macOS)
    static let columns = [GridItem(.adaptive(minimum: 420), spacing: 16, alignment: .top)]
    #else
    /// Narrower than the Mac's, since iPad's detail beside its sidebar can be narrower than 420 points.
    static let columns = [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)]
    #endif

    let title: String
    let lines: [MetricsChartLine]
    let format: MetricsValueFormat
    let timeline: MetricsTimeline
    /// Nil fits the figures, from 0.
    var yDomain: ClosedRange<Double>?
    /// Pages with more of what the chart shows, such as each filesystem's.
    var links: [MetricsChartLink] = []
    /// Nil takes the height it's given, as one chart at a time does.
    var height: CGFloat? = 150

    var id: String {
        title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MetricsChartLegend(title: title, lines: lines, format: format, timeline: timeline, links: links)
            chart
                .frame(height: height)
        }
        .padding(12)
        .background(.fill.quinary, in: .rect(cornerRadius: 10))
    }

    private var chart: some View {
        Chart {
            backupRuns
            ForEach(lines) { line in
                marks(line)
            }
        }
        .chartXScale(domain: timeline.domain)
        .chartYScale(domain: yDomain ?? fittedDomain)
        .chartYAxis {
            if let ticks = format.ticks(upTo: (yDomain ?? fittedDomain).upperBound) {
                AxisMarks(values: ticks) { value in
                    yAxisMark(value)
                }
            } else {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    yAxisMark(value)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) {
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            MomentOverlay(proxy: proxy, domain: timeline.domain)
        }
        .accessibilityLabel(title)
    }

    @AxisMarkBuilder private func yAxisMark(_ value: AxisValue) -> some AxisMark {
        AxisGridLine()
        AxisValueLabel {
            if let figure = value.as(Double.self) { Text(format.text(figure)) }
        }
    }

    /// From 0 to a little over the highest figure, and never so small that noise fills the chart.
    private var fittedDomain: ClosedRange<Double> {
        let highest = lines.flatMap(\.points).map { max($0.highest ?? $0.average, $0.base + $0.average) }.max() ?? 0
        let floor: Double = switch format {
        case .share: 0.05
        case .load, .perSecond: 1
        case .count: 10
        case .bytes, .bytesPerSecond: 1_024
        }
        return 0 ... max(highest * 1.1, floor)
    }

    @ChartContentBuilder private var backupRuns: some ChartContent {
        ForEach(Array(timeline.backupRuns.enumerated()), id: \.offset) { _, run in
            RectangleMark(
                xStart: .value("Backup start", MetricsTimeline.date(max(run.startedAt, timeline.range.lowerBound))),
                xEnd: .value("Backup end", MetricsTimeline.date(min(timeline.end(of: run), timeline.range.upperBound)))
            )
            .foregroundStyle(run.failure == nil ? Color.gray.opacity(0.16) : Color.red.opacity(0.14))
        }
    }

    @ChartContentBuilder private func marks(_ line: MetricsChartLine) -> some ChartContent {
        switch line.style {
        case .line:
            ForEach(line.points.filter { $0.highest != nil || $0.lowest != nil }, id: \.start) { point in
                AreaMark(
                    x: .value("Time", timeline.middle(of: point)),
                    yStart: .value("Lowest", point.lowest ?? point.average),
                    yEnd: .value("Highest", point.highest ?? point.average),
                    series: .value("Series", "\(line.name) range \(point.run)")
                )
                .foregroundStyle(line.color.opacity(0.2))
            }
            ForEach(line.points, id: \.start) { point in
                LineMark(
                    x: .value("Time", timeline.middle(of: point)),
                    y: .value(line.name, point.average),
                    series: .value("Series", "\(line.name) \(point.run)")
                )
                .foregroundStyle(line.color)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        case .stacked:
            ForEach(line.points, id: \.start) { point in
                AreaMark(
                    x: .value("Time", timeline.middle(of: point)),
                    yStart: .value("Base", point.base),
                    yEnd: .value(line.name, point.base + point.average),
                    series: .value("Series", "\(line.name) \(point.run)")
                )
                .foregroundStyle(line.color.opacity(0.75))
            }
        case .outline:
            ForEach(line.points, id: \.start) { point in
                LineMark(
                    x: .value("Time", timeline.middle(of: point)),
                    y: .value(line.name, point.average),
                    series: .value("Series", "\(line.name) \(point.run)")
                )
                .foregroundStyle(line.color)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
    }
}

/// A chart's title, and each line's figure at the moment shown, or its newest.
private struct MetricsChartLegend: View {
    let title: String
    let lines: [MetricsChartLine]
    let format: MetricsValueFormat
    let timeline: MetricsTimeline
    let links: [MetricsChartLink]

    @Environment(MetricsMoment.self) private var moment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                ForEach(links) { link in
                    Button(action: link.action) {
                        HStack(spacing: 2) {
                            Text(link.title)
                            Image(systemName: "chevron.forward")
                                .imageScale(.small)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let shown = moment.shown {
                    Text(timeline.time(shown))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            LegendLayout {
                ForEach(lines) { line in
                    HStack(spacing: 4) {
                        swatch(line)
                        Text(line.name)
                            .foregroundStyle(.secondary)
                        Text(value(of: line).map(format.text) ?? "—")
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    .accessibilityElement(children: .combine)
                }
                if let shown = moment.shown, let run = timeline.backupRun(at: shown) {
                    Label(run.failure == nil ? run.jobName : "\(run.jobName) failed", systemImage: "archivebox")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func swatch(_ line: MetricsChartLine) -> some View {
        switch line.style {
        case .line:
            Capsule().fill(line.color).frame(width: 10, height: 3)
        case .stacked:
            RoundedRectangle(cornerRadius: 2).fill(line.color.opacity(0.75)).frame(width: 9, height: 9)
        case .outline:
            Capsule().stroke(line.color, style: StrokeStyle(lineWidth: 1, dash: [2, 2])).frame(width: 10, height: 2)
        }
    }

    private func value(of line: MetricsChartLine) -> Double? {
        guard let shown = moment.shown else { return line.points.last?.average }
        return line.point(at: MetricsTimeline.second(shown), bucketSeconds: timeline.bucketSeconds)?.average
    }
}

/// Follows the pointer over a chart and chooses the moment clicked, with a rule at each.
private struct MomentOverlay: View {
    let proxy: ChartProxy
    let domain: ClosedRange<Date>

    @Environment(MetricsMoment.self) private var moment

    var body: some View {
        GeometryReader { geometry in
            let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): moment.hovered = date(at: location, in: plot)
                        case .ended: moment.hovered = nil
                        }
                    }
                    .gesture(
                        SpatialTapGesture().onEnded { tap in
                            moment.chosen = date(at: tap.location, in: plot)
                        }
                    )
                    #if os(iOS)
                    // Touch has no pointer to follow, so a finger held on the chart moves the moment
                    // instead, and lifting it chooses the moment there. A plain drag still scrolls.
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.25)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { value in
                                if case .second(true, let drag?) = value {
                                    moment.hovered = date(at: drag.location, in: plot)
                                }
                            }
                            .onEnded { value in
                                if case .second(true, let drag?) = value {
                                    moment.chosen = date(at: drag.location, in: plot)
                                }
                                moment.hovered = nil
                            }
                    )
                    #endif
                if let chosen = moment.chosen {
                    rule(at: chosen, in: plot)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
                if let hovered = moment.hovered {
                    rule(at: hovered, in: plot)
                        .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func rule(at date: Date, in plot: CGRect) -> Path {
        Path { path in
            guard let x = proxy.position(forX: date) else { return }
            path.move(to: CGPoint(x: plot.minX + x, y: plot.minY))
            path.addLine(to: CGPoint(x: plot.minX + x, y: plot.maxY))
        }
    }

    private func date(at location: CGPoint, in plot: CGRect) -> Date? {
        guard let date = proxy.value(atX: location.x - plot.minX, as: Date.self) else { return nil }
        return min(max(date, domain.lowerBound), domain.upperBound)
    }
}
