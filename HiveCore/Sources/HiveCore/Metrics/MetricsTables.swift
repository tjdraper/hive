import GRDB
import ScoutProtocol

/// What a figure keeps at the minute and hour resolutions, beside its average (§6).
enum MetricsKept: Sendable {
    /// For totals, such as a disk's size, whose highest is its average.
    case average
    case averageAndHighest
    /// For figures where a dip matters, such as available memory and space.
    case averageHighestAndLowest
}

struct MetricsColumn: Equatable, Sendable {
    let name: String
    /// Bytes and counts. Their averages are rounded, so they're stored as integers.
    let isWhole: Bool
    let kept: MetricsKept

    var highest: String? {
        kept == .average ? nil : "\(name)Highest"
    }

    var lowest: String? {
        kept == .averageHighestAndLowest ? "\(name)Lowest" : nil
    }
}

struct MetricsFigure<Source>: Sendable {
    let column: MetricsColumn
    let value: @Sendable (Source) -> DatabaseValue

    static func real(_ name: String, kept: MetricsKept = .averageAndHighest, _ value: @escaping @Sendable (Source) -> Double?) -> Self {
        MetricsFigure(column: MetricsColumn(name: name, isWhole: false, kept: kept)) { value($0)?.databaseValue ?? .null }
    }

    static func bytes(_ name: String, kept: MetricsKept = .averageAndHighest, _ value: @escaping @Sendable (Source) -> UInt64?) -> Self {
        MetricsFigure(column: MetricsColumn(name: name, isWhole: true, kept: kept)) {
            value($0).map { Int64(clamping: $0) }?.databaseValue ?? .null
        }
    }

    static func count(_ name: String, kept: MetricsKept = .averageAndHighest, _ value: @escaping @Sendable (Source) -> Int?) -> Self {
        MetricsFigure(column: MetricsColumn(name: name, isWhole: true, kept: kept)) { value($0)?.databaseValue ?? .null }
    }
}

/// The figures of one kind, such as a server's or each filesystem's, with a table for each resolution.
protocol MetricsTableShape: Sendable {
    var kind: String { get }
    /// `metricsName.kind` for figures kept by name, or nil for the server's own.
    var nameKind: String? { get }
    var columns: [MetricsColumn] { get }
}

extension MetricsTableShape {
    /// `serverKey`, or `nameID` for figures kept by name, which belong to a server through their name.
    var keyColumn: String {
        nameKind == nil ? "serverKey" : "nameID"
    }

    func table(_ resolution: MetricsResolution) -> String {
        "\(kind)\(resolution.tableSuffix)"
    }

    /// Every figure column of the table at `resolution`, in order.
    func figureColumns(_ resolution: MetricsResolution) -> [String] {
        guard resolution != .tenSeconds else { return columns.map(\.name) }
        return columns.flatMap { [$0.name, $0.highest, $0.lowest].compactMap(\.self) }
    }
}

struct MetricsTable<Source>: MetricsTableShape {
    let kind: String
    let nameKind: String?
    let figures: [MetricsFigure<Source>]

    var columns: [MetricsColumn] {
        figures.map(\.column)
    }

    /// The values for a 10-second row, in `figureColumns(.tenSeconds)`'s order.
    func values(of source: Source) -> [DatabaseValue] {
        figures.map { $0.value(source) }
    }

    /// The values for a minute's row from a backlog, in `figureColumns(.minute)`'s order. `lowest` holds
    /// the minute's lows where it keeps them, and its average elsewhere.
    func values(average: Source, highest: Source, lowest: Source) -> [DatabaseValue] {
        figures.flatMap { figure in
            switch figure.column.kept {
            case .average: [figure.value(average)]
            case .averageAndHighest: [figure.value(average), figure.value(highest)]
            case .averageHighestAndLowest: [figure.value(average), figure.value(highest), figure.value(lowest)]
            }
        }
    }
}

/// A server's own figures, from a sample or a minute.
struct ServerWideFigures: Sendable {
    var cpu: CPUFigures?
    var memory: MemoryFigures?
    var pressure: PressureFigures?
    var processes: ProcessFigures?
}

enum MetricsTables {
    static let filesystemKind = "filesystem"
    static let diskKind = "disk"
    static let networkInterfaceKind = "networkInterface"

    static let server = MetricsTable<ServerWideFigures>(kind: "server", nameKind: nil, figures: [
        .count("cores", kept: .average) { $0.cpu?.cores },
        .real("cpuUser") { $0.cpu?.use?.user },
        .real("cpuSystem") { $0.cpu?.use?.system },
        .real("cpuIOWait") { $0.cpu?.use?.ioWait },
        .real("cpuSteal") { $0.cpu?.use?.steal },
        .real("loadOneMinute") { $0.cpu?.load?.oneMinute },
        .real("loadFiveMinutes") { $0.cpu?.load?.fiveMinutes },
        .real("loadFifteenMinutes") { $0.cpu?.load?.fifteenMinutes },
        .bytes("memoryTotal", kept: .average) { $0.memory?.totalBytes },
        .bytes("memoryAvailable", kept: .averageHighestAndLowest) { $0.memory?.availableBytes },
        .bytes("memoryCache") { $0.memory?.cacheBytes },
        .bytes("swapTotal", kept: .average) { $0.memory?.swapTotalBytes },
        .bytes("swapUsed") { $0.memory?.swapUsedBytes },
        .real("swapInPages") { $0.memory?.swapping?.pagesInPerSecond },
        .real("swapOutPages") { $0.memory?.swapping?.pagesOutPerSecond },
        .real("pressureCPUSome") { $0.pressure?.cpu?.some },
        .real("pressureCPUFull") { $0.pressure?.cpu?.full },
        .real("pressureMemorySome") { $0.pressure?.memory?.some },
        .real("pressureMemoryFull") { $0.pressure?.memory?.full },
        .real("pressureIOSome") { $0.pressure?.inputOutput?.some },
        .real("pressureIOFull") { $0.pressure?.inputOutput?.full },
        .count("processes") { $0.processes?.count },
        .count("zombies") { $0.processes?.zombies },
    ])

    static let filesystem = MetricsTable<FilesystemFigures>(kind: filesystemKind, nameKind: filesystemKind, figures: [
        .bytes("size", kept: .average) { $0.space?.sizeBytes },
        .bytes("used") { $0.space?.usedBytes },
        .bytes("available", kept: .averageHighestAndLowest) { $0.space?.availableBytes },
        .bytes("inodesUsed") { $0.space?.inodes?.used },
        .bytes("inodesFree", kept: .averageHighestAndLowest) { $0.space?.inodes?.free },
    ])

    static let disk = MetricsTable<DiskFigures>(kind: diskKind, nameKind: diskKind, figures: [
        .real("readBytes") { $0.activity?.readBytesPerSecond },
        .real("writtenBytes") { $0.activity?.writtenBytesPerSecond },
        .real("reads") { $0.activity?.readsPerSecond },
        .real("writes") { $0.activity?.writesPerSecond },
        .real("busy") { $0.activity?.busy },
    ])

    static let networkInterface = MetricsTable<NetworkInterfaceFigures>(
        kind: networkInterfaceKind,
        nameKind: networkInterfaceKind,
        figures: [
            .real("receivedBytes") { $0.traffic?.receivedBytesPerSecond },
            .real("sentBytes") { $0.traffic?.sentBytesPerSecond },
            .real("receiveErrors") { $0.traffic?.receiveErrorsPerSecond },
            .real("sendErrors") { $0.traffic?.sendErrorsPerSecond },
            .real("receiveDrops") { $0.traffic?.receiveDropsPerSecond },
            .real("sendDrops") { $0.traffic?.sendDropsPerSecond },
        ]
    )

    static let all: [any MetricsTableShape] = [server, filesystem, disk, networkInterface]
}
