import HiveKit
import SwiftUI

/// A server's container groups and services over a range, as stacked areas on its charts: the busiest
/// few each in a color of its own, kept on every chart and list of the page, and the rest together.
struct CgroupHistory {
    /// More would leave too little of each color to tell apart.
    private static let namedGroups = 5
    private static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .brown, .indigo, .yellow, .mint]

    let bucketSeconds: Int64
    let containers: [CgroupGroupSeries]
    let services: [CgroupGroupSeries]
    private let colors: [String: Color]

    /// `range` is seconds since 1970 on the server's clock, as a `ServerHistory` read it.
    static func read(over range: Range<Int64>, ofServer serverID: UUID, from link: HiveLink) async throws -> CgroupHistory {
        let path = HiveEndpoint.containerSeries(ofServer: serverID, from: range.lowerBound, to: range.upperBound)
        return try await CgroupHistory(series: link.perform { try await $0.get(path, as: CgroupSeries.self) })
    }

    init(series: CgroupSeries) {
        bucketSeconds = series.bucketSeconds
        containers = series.containers
        services = series.services
        var colors: [String: Color] = [:]
        for groups in [series.containers, series.services] {
            let ranked = Self.busiest(groups, by: \.averageCPUCores) + Self.busiest(groups, by: \.averageMemoryBytes)
            var next = 0
            for group in ranked where colors[Self.key(group)] == nil {
                colors[Self.key(group)] = Self.palette[next % Self.palette.count]
                next += 1
            }
        }
        self.colors = colors
    }

    /// A group's color on the page's charts and lists. Nil for one in none of the charts.
    func color(name: String, composeProject: String?) -> Color? {
        colors[Self.key(name: name, composeProject: composeProject)]
    }

    func cpu(of groups: [CgroupGroupSeries]) -> [MetricsChartLine] {
        lines(groups, figure: \.averageCPUCores)
    }

    /// Empty where the server doesn't account for its containers' memory.
    func memory(of groups: [CgroupGroupSeries]) -> [MetricsChartLine] {
        guard groups.contains(where: { $0.averageMemoryBytes.contains { $0 > 0 } }) else { return [] }
        return lines(groups, figure: \.averageMemoryBytes)
    }

    /// The busiest groups at their peak in the range, so one busy only briefly still has a color of its
    /// own, and the rest stacked on top as Others. Each line holds a bucket for every one kept, a group
    /// missing from it as nothing.
    private func lines(_ groups: [CgroupGroupSeries], figure: KeyPath<CgroupGroupSeries, [Double]>) -> [MetricsChartLine] {
        let named = Self.busiest(groups, by: figure)
        guard let starts = groups.first?.bucketStarts, !named.isEmpty else { return [] }
        var lines = named.map { group in
            line(Self.name(group), color: colors[Self.key(group)] ?? .gray, starts: starts, values: group[keyPath: figure])
        }
        let namedKeys = Set(named.map(Self.key))
        let others = groups.filter { !namedKeys.contains(Self.key($0)) }
        if !others.isEmpty {
            let values = starts.indices.map { index in others.reduce(0) { $0 + $1[keyPath: figure][index] } }
            lines.append(line("Others", color: .gray, starts: starts, values: values))
        }
        return MetricsChartLine.stacked(lines)
    }

    private func line(_ name: String, color: Color, starts: [Int64], values: [Double]) -> MetricsChartLine {
        var points: [MetricsChartPoint] = []
        var run = 0
        for (index, start) in starts.enumerated() {
            if let previous = points.last, start - previous.start > bucketSeconds { run += 1 }
            points.append(MetricsChartPoint(start: start, run: run, average: values[index], highest: nil, lowest: nil))
        }
        return MetricsChartLine(name: name, color: color, points: points)
    }

    private static func busiest(_ groups: [CgroupGroupSeries], by figure: KeyPath<CgroupGroupSeries, [Double]>) -> [CgroupGroupSeries] {
        groups
            .map { (group: $0, peak: $0[keyPath: figure].max() ?? 0) }
            .filter { $0.peak > 0 }
            .sorted { $0.peak > $1.peak }
            .prefix(namedGroups)
            .map(\.group)
    }

    /// Every Compose project has its own `db`, so its project names it too.
    nonisolated static func name(_ name: String, composeProject: String?) -> String {
        composeProject.map { "\($0) › \(name)" } ?? name
    }

    private static func name(_ group: CgroupGroupSeries) -> String {
        name(group.name, composeProject: group.composeProject)
    }

    private static func key(_ group: CgroupGroupSeries) -> String {
        key(name: group.name, composeProject: group.composeProject)
    }

    private static func key(name: String, composeProject: String?) -> String {
        "\(composeProject ?? "")/\(name)"
    }
}
