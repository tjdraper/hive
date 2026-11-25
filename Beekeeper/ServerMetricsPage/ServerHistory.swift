import HiveKit
import SwiftUI

/// A server's figures over a range, as the lines of its charts.
struct ServerHistory {
    static let figures: [MetricsFigure] = [
        .cores, .cpuUser, .cpuSystem, .cpuIOWait, .cpuSteal, .loadOneMinute,
        .memoryTotal, .memoryAvailable, .memoryCache, .swapTotal, .swapUsed, .swapInPages, .swapOutPages,
        .pressureCPUSome, .pressureMemorySome, .pressureIOSome,
        .filesystemUsed, .filesystemAvailable,
        .diskReadBytes, .diskWrittenBytes,
        .networkReceivedBytes, .networkSentBytes,
    ]

    /// For lines that stand for names, such as each filesystem, which have no color of their own.
    private static let palette: [Color] = [
        Color(.metricsCPU), Color(.metricsMemory), .orange, .purple, .teal, .pink, .brown, .indigo,
    ]

    /// Seconds since 1970 on the server's clock.
    let range: Range<Int64>
    let bucketSeconds: Int64
    let backupRuns: [BackupRunMark]
    let filesystems: [SubjectFigures]
    let disks: [SubjectFigures]
    let interfaces: [SubjectFigures]
    private let server: SubjectFigures?

    /// The server's state, and `figures` over the range ending now on the server's clock, which Hive
    /// knows the offset of.
    static func read(
        _ figures: [MetricsFigure],
        over range: MetricsRange,
        ofServer serverID: UUID,
        from link: HiveLink
    ) async throws -> (state: ServerMetricsState, history: ServerHistory) {
        let state = try await link.perform {
            try await $0.get(HiveEndpoint.metrics(ofServer: serverID), as: ServerMetricsState.self)
        }
        let end = Int64(Date.now.timeIntervalSince1970.rounded(.down)) + Int64(state.scout?.clockOffsetSeconds ?? 0)
        let span = end - range.seconds ..< end
        let seriesPath = HiveEndpoint.metricsSeries(ofServer: serverID, from: span.lowerBound, to: span.upperBound, figures: figures)
        let series = try await link.perform { try await $0.get(seriesPath, as: MetricsSeries.self) }
        let runs = try await link.perform {
            try await $0.get(
                HiveEndpoint.backupRunMarks(ofServer: serverID, from: span.lowerBound, to: span.upperBound),
                as: [BackupRunMark].self
            )
        }
        return (state, ServerHistory(series: series, range: span, backupRuns: runs))
    }

    init(series: MetricsSeries, range: Range<Int64>, backupRuns: [BackupRunMark]) {
        self.range = range
        self.backupRuns = backupRuns
        bucketSeconds = series.bucketSeconds
        let subjects = series.subjects.map { SubjectFigures($0, bucketSeconds: series.bucketSeconds) }
        server = subjects.first { $0.kind == .server }
        filesystems = subjects.filter { $0.kind == .filesystem }
        disks = subjects.filter { $0.kind == .disk }
        interfaces = subjects.filter { $0.kind == .networkInterface }
    }

    /// Each part stacked, so the top is all the time the CPU was busy. Hive keeps each part's highest
    /// apart, so their sum can overstate a bucket's busiest moment when the parts peaked at different
    /// times. A 10-second bucket is one sample, with no highest of its own.
    var cpu: [MetricsChartLine] {
        guard let server else { return [] }
        let parts: [(name: String, figure: MetricsFigure)] = [
            ("User", .cpuUser), ("System", .cpuSystem), ("I/O wait", .cpuIOWait), ("Steal", .cpuSteal),
        ]
        let colors = [Color(.metricsCPU), .orange, .purple, .red]
        // A Mac counts neither I/O wait nor steal.
        let shown = zip(parts, colors).filter { [.cpuUser, .cpuSystem].contains($0.0.figure) || server.largest($0.0.figure) != nil }
        var lines = MetricsChartLine.stacked(shown.map { server.line($0.name, color: $1, figure: $0.figure) })
        if bucketSeconds > 10 {
            lines.append(server.line("Highest", color: .secondary, style: .outline) { index in
                let highs = shown.map { server.highest($0.0.figure, index) ?? server.average($0.0.figure, index) }
                guard highs.allSatisfy({ $0 != nil }) else { return nil }
                return SubjectFigures.Reading(average: min(1, highs.compactMap(\.self).reduce(0, +)))
            })
        }
        return lines
    }

    var load: [MetricsChartLine] {
        guard let server else { return [] }
        return [
            server.line("Load", color: Color(.metricsCPU), figure: .loadOneMinute),
            server.line("Cores", color: .secondary, style: .outline) { index in
                server.average(.cores, index).map { SubjectFigures.Reading(average: $0) }
            },
        ]
    }

    /// In use is the total less what's available, so its highest comes from available's lowest.
    var memory: [MetricsChartLine] {
        guard let server else { return [] }
        let inUse = server.line("In use", color: Color(.metricsMemory)) { index in
            guard let total = server.average(.memoryTotal, index),
                  let available = server.average(.memoryAvailable, index)
            else { return nil }
            return SubjectFigures.Reading(
                average: total - available,
                highest: server.lowest(.memoryAvailable, index).map { total - $0 },
                lowest: server.highest(.memoryAvailable, index).map { total - $0 }
            )
        }
        return [inUse, server.line("Cache", color: .teal, figure: .memoryCache)]
    }

    var cores: Double? {
        server?.largest(.cores)
    }

    var memoryTotal: Double? {
        server?.largest(.memoryTotal)
    }

    /// Nil when the server had no swap in the range.
    var swapTotal: Double? {
        server?.largest(.swapTotal).flatMap { $0 > 0 ? $0 : nil }
    }

    var swap: [MetricsChartLine] {
        guard let server else { return [] }
        return [server.line("In use", color: .orange, figure: .swapUsed)]
    }

    /// Swapping in steadily means the server is short of memory; swap merely in use is often harmless.
    var swapping: [MetricsChartLine] {
        guard let server else { return [] }
        return [
            server.line("In", color: .pink, figure: .swapInPages),
            server.line("Out", color: .teal, figure: .swapOutPages),
        ]
    }

    /// Empty where the server's kernel doesn't report pressure.
    var pressure: [MetricsChartLine] {
        guard let server else { return [] }
        return [
            server.line("CPU", color: Color(.metricsCPU), figure: .pressureCPUSome),
            server.line("Memory", color: Color(.metricsMemory), figure: .pressureMemorySome),
            server.line("I/O", color: .purple, figure: .pressureIOSome),
        ]
        .filter { !$0.points.isEmpty }
    }

    /// Zombies have exited, but their parent hasn't collected them.
    var processCount: [MetricsChartLine] {
        guard let server else { return [] }
        return [
            server.line("Processes", color: Color(.metricsCPU), figure: .processes),
            server.line("Zombies", color: .red, figure: .zombies),
        ]
    }

    /// Each filesystem's share used, of what's usable without root's reserve, as `df` shows it.
    var diskSpace: [MetricsChartLine] {
        filesystems.map { filesystem in
            filesystem.line(filesystem.name ?? "", color: color(of: filesystem)) { index in
                guard let used = filesystem.average(.filesystemUsed, index),
                      let available = filesystem.average(.filesystemAvailable, index),
                      used + available > 0
                else { return nil }
                let usable = used + available
                return SubjectFigures.Reading(
                    average: used / usable,
                    highest: filesystem.lowest(.filesystemAvailable, index).map { (usable - $0) / usable },
                    lowest: filesystem.highest(.filesystemAvailable, index).map { (usable - $0) / usable }
                )
            }
        }
    }

    /// The same on every chart a filesystem is on.
    func color(of filesystem: SubjectFigures) -> Color {
        Self.palette[(filesystems.firstIndex { $0.id == filesystem.id } ?? 0) % Self.palette.count]
    }

    /// Bytes used, of what's usable without root's reserve, so the band's highest comes from available's lowest.
    func space(of filesystem: SubjectFigures) -> [MetricsChartLine] {
        let used = filesystem.line("Used", color: color(of: filesystem)) { index in
            guard let used = filesystem.average(.filesystemUsed, index),
                  let available = filesystem.average(.filesystemAvailable, index)
            else { return nil }
            let usable = used + available
            return SubjectFigures.Reading(
                average: used,
                highest: filesystem.lowest(.filesystemAvailable, index).map { usable - $0 },
                lowest: filesystem.highest(.filesystemAvailable, index).map { usable - $0 }
            )
        }
        return [used]
    }

    /// Empty for filesystems without a fixed number of inodes, such as Btrfs.
    func inodes(of filesystem: SubjectFigures) -> [MetricsChartLine] {
        let used = filesystem.line("Used", color: color(of: filesystem)) { index in
            guard let used = filesystem.average(.filesystemInodesUsed, index),
                  let free = filesystem.average(.filesystemInodesFree, index),
                  used + free > 0
            else { return nil }
            let total = used + free
            return SubjectFigures.Reading(
                average: used / total,
                highest: filesystem.lowest(.filesystemInodesFree, index).map { (total - $0) / total },
                lowest: filesystem.highest(.filesystemInodesFree, index).map { (total - $0) / total }
            )
        }
        return used.points.isEmpty ? [] : [used]
    }

    /// The disk a filesystem is on, by its device's name: `/dev/vdb1` is on `vdb`, and `/dev/nvme0n1p2`
    /// on `nvme0n1`. Nil for loop devices and those layered on disks, such as LVM's, which Scout
    /// doesn't send as disks.
    func disk(holding filesystem: SubjectFigures) -> SubjectFigures? {
        guard let device = filesystem.device, device.hasPrefix("/dev/") else { return nil }
        let name = device.dropFirst("/dev/".count)
        return disks.first { disk in
            guard let diskName = disk.name, name.hasPrefix(diskName) else { return false }
            var partition = name.dropFirst(diskName.count)
            if diskName.last?.isNumber == true, partition.first == "p" { partition = partition.dropFirst() }
            return partition.allSatisfy(\.isNumber)
        }
    }

    func busy(of disk: SubjectFigures) -> [MetricsChartLine] {
        [disk.line("Busy", color: .purple, figure: .diskBusy)]
    }

    func activity(of disk: SubjectFigures) -> [MetricsChartLine] {
        [
            disk.line("Read", color: .teal, figure: .diskReadBytes),
            disk.line("Written", color: .orange, figure: .diskWrittenBytes),
        ]
    }

    func traffic(of interface: SubjectFigures) -> [MetricsChartLine] {
        [
            interface.line("Received", color: .teal, figure: .networkReceivedBytes),
            interface.line("Sent", color: .orange, figure: .networkSentBytes),
        ]
    }
}

/// A subject's figures by bucket: the server's own, or one filesystem's, disk's or interface's.
struct SubjectFigures: Identifiable {
    struct Reading {
        let average: Double
        var highest: Double?
        var lowest: Double?
    }

    let kind: MetricsSubjectKind
    let name: String?
    /// A filesystem's device, such as `/dev/vda1`, and type, such as `ext4`.
    let device: String?
    let filesystemType: String?
    private let bucketSeconds: Int64
    private let bucketStarts: [Int64]
    private let figures: [MetricsFigure: MetricsFigureSeries]

    var id: String {
        "\(kind.rawValue) \(name ?? "")"
    }

    init(_ subject: MetricsSeriesSubject, bucketSeconds: Int64) {
        kind = subject.kind
        name = subject.name
        device = subject.device
        filesystemType = subject.filesystemType
        self.bucketSeconds = bucketSeconds
        bucketStarts = subject.bucketStarts
        figures = Dictionary(subject.figures.map { ($0.figure, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func average(_ figure: MetricsFigure, _ index: Int) -> Double? {
        figures[figure]?.average[index]
    }

    func highest(_ figure: MetricsFigure, _ index: Int) -> Double? {
        figures[figure]?.highest?[index]
    }

    func lowest(_ figure: MetricsFigure, _ index: Int) -> Double? {
        figures[figure]?.lowest?[index]
    }

    func newest(_ figure: MetricsFigure) -> Double? {
        figures[figure]?.average.compactMap(\.self).last
    }

    func largest(_ figure: MetricsFigure) -> Double? {
        figures[figure]?.average.compactMap(\.self).max()
    }

    func line(_ name: String, color: Color, figure: MetricsFigure) -> MetricsChartLine {
        line(name, color: color) { index in
            average(figure, index).map { Reading(average: $0, highest: highest(figure, index), lowest: lowest(figure, index)) }
        }
    }

    /// Each bucket's reading, with a new run after each gap or bucket without one.
    func line(
        _ name: String,
        color: Color,
        style: MetricsChartLine.Style = .line,
        reading: (Int) -> Reading?
    ) -> MetricsChartLine {
        var points: [MetricsChartPoint] = []
        var run = 0
        var previous: Int64?
        for (index, start) in bucketStarts.enumerated() {
            guard let value = reading(index) else {
                previous = nil
                continue
            }
            if !points.isEmpty, previous.map({ start - $0 > bucketSeconds }) ?? true { run += 1 }
            points.append(MetricsChartPoint(start: start, run: run, average: value.average, highest: value.highest, lowest: value.lowest))
            previous = start
        }
        return MetricsChartLine(name: name, color: color, style: style, points: points)
    }
}
