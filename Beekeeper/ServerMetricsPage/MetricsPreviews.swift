#if DEBUG && os(iOS)
import HiveKit
import SwiftUI

/// A server's made-up last hour, and a dashboard of servers in each state, for the iPhone layouts. A
/// simulator can't sign in to a Hive, so these are how the layouts are seen without a device.
enum MetricsPreviewData {
    static let end = Int64(Date.now.timeIntervalSince1970.rounded(.down))
    static let range = end - 3_600 ..< end
    static let starts = Array(stride(from: range.lowerBound, to: range.upperBound, by: 10))

    /// A wave with a spike 20 minutes ago, so a chart has something to choose.
    static func wave(_ base: Double, _ swing: Double, spike: Double = 0) -> [Double?] {
        starts.enumerated().map { index, start in
            let spiking = abs(start - (end - 1_200)) < 120
            return base + swing * sin(Double(index) / 9) + (spiking ? spike : 0)
        }
    }

    static func series(_ figure: MetricsFigure, _ values: [Double?]) -> MetricsFigureSeries {
        MetricsFigureSeries(figure: figure, average: values, highest: nil, lowest: nil)
    }

    static func constant(_ value: Double) -> [Double?] {
        starts.map { _ in value }
    }

    static let history: ServerHistory = {
        let gigabyte = 1_073_741_824.0
        let server = MetricsSeriesSubject(kind: .server, name: nil, bucketStarts: starts, figures: [
            series(.cores, constant(4)),
            series(.cpuUser, wave(0.12, 0.05, spike: 0.55)),
            series(.cpuSystem, wave(0.04, 0.02, spike: 0.1)),
            series(.cpuIOWait, wave(0.01, 0.005)),
            series(.cpuSteal, wave(0.005, 0.003)),
            series(.loadOneMinute, wave(0.8, 0.3, spike: 2.4)),
            series(.memoryTotal, constant(8 * gigabyte)),
            series(.memoryAvailable, wave(3.2 * gigabyte, 0.2 * gigabyte, spike: -1 * gigabyte)),
            series(.memoryCache, wave(2.1 * gigabyte, 0.05 * gigabyte)),
            series(.processes, wave(312, 6)),
            series(.zombies, constant(0)),
        ])
        let root = MetricsSeriesSubject(
            kind: .filesystem, name: "/", device: "/dev/vda1", filesystemType: "ext4", bucketStarts: starts, figures: [
                series(.filesystemUsed, constant(31 * gigabyte)),
                series(.filesystemAvailable, constant(17 * gigabyte)),
            ]
        )
        let home = MetricsSeriesSubject(
            kind: .filesystem, name: "/home", device: "/dev/vdb1", filesystemType: "ext4", bucketStarts: starts, figures: [
                series(.filesystemUsed, wave(80 * gigabyte, 0.5 * gigabyte)),
                series(.filesystemAvailable, wave(20 * gigabyte, 0.5 * gigabyte)),
            ]
        )
        let disk = MetricsSeriesSubject(kind: .disk, name: "vda", bucketStarts: starts, figures: [
            series(.diskReadBytes, wave(400_000, 300_000)),
            series(.diskWrittenBytes, wave(1_200_000, 600_000, spike: 8_000_000)),
        ])
        let network = MetricsSeriesSubject(kind: .networkInterface, name: "eth0", bucketStarts: starts, figures: [
            series(.networkReceivedBytes, wave(90_000, 40_000)),
            series(.networkSentBytes, wave(240_000, 100_000)),
        ])
        return ServerHistory(
            series: MetricsSeries(bucketSeconds: 10, subjects: [server, root, home, disk, network]),
            range: range,
            backupRuns: [
                BackupRunMark(jobID: UUID(), jobName: "Example Site", startedAt: end - 2_400, finishedAt: end - 2_100, failure: nil),
            ]
        )
    }()

    static let scout = ScoutState(
        enrolledAt: .now.addingTimeInterval(-86_400 * 30),
        lastSeenAt: .now,
        lastReportAt: .now,
        version: "0.3.0",
        platform: "linux-x86_64",
        distribution: "Debian GNU/Linux 13 (trixie)",
        kernel: "6.12.48-1",
        startedAt: end - 86_400 * 12 - 4_000,
        clockOffsetSeconds: 0,
        processesHidden: false,
        lastRefusal: nil,
        update: nil
    )

    static func server(_ name: String, _ reporting: MetricsReporting, cpu: Double, memory: Double, disk: Double) -> DashboardServer {
        let gigabyte: UInt64 = 1_073_741_824
        let latest = ServerMetricsLatest(
            serverID: UUID(),
            takenAt: end,
            cores: 4,
            cpu: CPUShares(user: cpu * 0.8, system: cpu * 0.2, ioWait: 0, steal: 0),
            load: LoadFigures(oneMinute: cpu * 4, fiveMinutes: cpu * 4, fifteenMinutes: cpu * 4),
            memory: MemoryUse(
                totalBytes: 8 * gigabyte,
                availableBytes: UInt64(Double(8 * gigabyte) * (1 - memory)),
                swapTotalBytes: 2 * gigabyte,
                swapUsedBytes: gigabyte / 8
            ),
            fullestFilesystem: FilesystemUse(
                mountPoint: "/",
                sizeBytes: 50 * gigabyte,
                usedBytes: UInt64(Double(50 * gigabyte) * disk),
                availableBytes: UInt64(Double(50 * gigabyte) * (1 - disk))
            )
        )
        let summary = ServerMetricsSummary(
            serverID: latest.serverID,
            reporting: reporting,
            lastReportAt: .now.addingTimeInterval(reporting == .stopped ? -2_700 : 0),
            latest: latest,
            lastHour: []
        )
        return DashboardServer(name: name, summary: summary, live: nil)
    }

    static let dashboard = [
        server("buzzingpixel-hetzner-docker", .stopped, cpu: 0.2, memory: 0.5, disk: 0.6),
        server("mail", .reporting, cpu: 0.95, memory: 0.4, disk: 0.93),
        server("B3 Debian root", .reporting, cpu: 0.12, memory: 0.38, disk: 0.64),
        server("Test: A4 Alpine", .reporting, cpu: 0.03, memory: 0.21, disk: 0.12),
    ]
}

#Preview("Dashboard on iPhone") {
    NavigationStack {
        List(MetricsPreviewData.dashboard) { server in
            HStack {
                ServerMetricsRow(server: server)
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.tertiary)
            }
        }
        .navigationTitle("Metrics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("A server's charts") {
    ServerChartsPreview()
}

/// One chart at a time at iPhone width, and the grid otherwise, as on iPad.
private struct ServerChartsPreview: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var range = MetricsRange.hour
    @State private var shown: MetricsChart.ID?
    @State private var moment = MetricsMoment()

    var body: some View {
        NavigationStack {
            ScrollView {
                if sizeClass == .compact {
                    VStack(alignment: .leading, spacing: 12) {
                        MetricsRangePicker(range: $range)
                            .padding(.horizontal)
                        MetricsChartPager(charts: charts, shown: $shown)
                            .frame(height: 320)
                        facts
                            .padding(.horizontal)
                    }
                    .padding(.vertical)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        facts
                        LazyVGrid(columns: MetricsChart.columns, spacing: 16) {
                            ForEach(charts) { $0 }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("B3 Debian root")
            .navigationBarTitleDisplayMode(.inline)
            .metricsRangeToolbar($range)
        }
        .environment(moment)
    }

    private var facts: some View {
        ServerFacts(scout: MetricsPreviewData.scout, history: MetricsPreviewData.history, serverNow: MetricsPreviewData.end)
    }

    private var charts: [MetricsChart] {
        let history = MetricsPreviewData.history
        let timeline = MetricsTimeline(history: history)
        return [
            MetricsChart(title: "CPU", lines: history.cpu, format: .share, timeline: timeline, yDomain: 0 ... 1),
            MetricsChart(title: "Load", lines: history.load, format: .load, timeline: timeline),
            MetricsChart(title: "Memory", lines: history.memory, format: .bytes, timeline: timeline),
            MetricsChart(title: "Disk space used", lines: history.diskSpace, format: .share, timeline: timeline, yDomain: 0 ... 1),
        ]
    }
}
#endif
