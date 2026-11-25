import Foundation
import GRDB
import HiveKit
import ScoutProtocol

/// A group of containers as Hive names them (§4), or a systemd service. Swarm replicas share their
/// service, so `buzzingpixel_db.1.<id>` and its replacement are one group; a Compose service is its
/// project's, so each project's `db` stays its own.
struct CgroupGroupKey: Codable, Hashable, Sendable {
    let name: String
    let kind: ContainerGroupKind?
    let composeProject: String?

    static func container(_ id: String, named container: ContainerName?) -> CgroupGroupKey {
        if let service = container?.swarmService {
            return CgroupGroupKey(name: service, kind: .swarmService, composeProject: nil)
        }
        if let service = container?.composeService {
            return CgroupGroupKey(name: service, kind: .composeService, composeProject: container?.composeProject)
        }
        if let name = container?.name {
            return CgroupGroupKey(name: name, kind: .container, composeProject: nil)
        }
        return CgroupGroupKey(name: String(id.prefix(12)), kind: .unnamed, composeProject: nil)
    }

    static func service(_ unit: String) -> CgroupGroupKey {
        CgroupGroupKey(name: unit, kind: nil, composeProject: nil)
    }
}

/// A group over an hour, as the hourly pass keeps it for 90 days (§6).
struct HourlyCgroupGroup: Codable, Equatable, Sendable {
    let key: CgroupGroupKey
    let highestContainerCount: Int
    let averageCPUCores: Double
    let highestCPUCores: Double
    let averageMemoryBytes: Double
    let highestMemoryBytes: Double
    let commands: [String]

    var figures: CgroupGroupFigures {
        CgroupGroupFigures(
            name: key.name,
            kind: key.kind,
            composeProject: key.composeProject,
            containerCount: highestContainerCount,
            cpuCores: averageCPUCores,
            highestCPUCores: highestCPUCores,
            memoryBytes: UInt64(averageMemoryBytes.rounded()),
            highestMemoryBytes: UInt64(highestMemoryBytes.rounded()),
            readBytesPerSecond: nil,
            writtenBytesPerSecond: nil,
            processes: nil,
            commands: commands,
            containers: []
        )
    }
}

enum CgroupGrouping {
    static let topCountByEachMeasure = 10
    static let largestCommandCount = 3

    /// A sample's containers by group, busiest first.
    static func containers(_ figures: CgroupFigures, names: [String: ContainerName]) -> [CgroupGroupFigures] {
        var members: [CgroupGroupKey: [CgroupUse]] = [:]
        var order: [CgroupGroupKey] = []
        for use in figures.top {
            let key = CgroupGroupKey.container(use.name, named: names[use.name])
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(use)
        }
        return sortedByCPU(order.map { key in
            let uses = members[key] ?? []
            var commands: [String] = []
            for command in uses.flatMap(\.commands) where !commands.contains(command) {
                commands.append(command)
            }
            return CgroupGroupFigures(
                name: key.name,
                kind: key.kind,
                composeProject: key.composeProject,
                containerCount: uses.count,
                cpuCores: total(uses.map(\.cpuCores)),
                highestCPUCores: nil,
                memoryBytes: total(uses.map { $0.memoryBytes.map { Double($0) } }).map { UInt64($0) },
                highestMemoryBytes: nil,
                readBytesPerSecond: total(uses.map(\.readBytesPerSecond)),
                writtenBytesPerSecond: total(uses.map(\.writtenBytesPerSecond)),
                processes: uses.reduce(0) { $0 + $1.processes },
                commands: Array(commands.prefix(largestCommandCount)),
                containers: uses.map { use in
                    ContainerFigures(
                        id: use.name,
                        name: names[use.name]?.name,
                        cpuCores: use.cpuCores,
                        memoryBytes: use.memoryBytes,
                        processes: use.processes,
                        commands: use.commands
                    )
                }
            )
        })
    }

    static func services(_ figures: CgroupFigures) -> [CgroupGroupFigures] {
        sortedByCPU(figures.top.map { use in
            CgroupGroupFigures(
                name: use.name,
                kind: nil,
                composeProject: nil,
                containerCount: 1,
                cpuCores: use.cpuCores,
                highestCPUCores: nil,
                memoryBytes: use.memoryBytes,
                highestMemoryBytes: nil,
                readBytesPerSecond: use.readBytesPerSecond,
                writtenBytesPerSecond: use.writtenBytesPerSecond,
                processes: use.processes,
                commands: [],
                containers: []
            )
        })
    }

    /// Each group's average and highest over samples, a sample it's missing from counting as nothing,
    /// so averages are at least what's shown. `samples` holds each sample's groups.
    static func combined(_ samples: [[CgroupGroupFigures]]) -> [HourlyCgroupGroup] {
        struct Totals {
            var highestContainerCount = 0
            var cpuCores = 0.0
            var highestCPUCores = 0.0
            var memoryBytes = 0.0
            var highestMemoryBytes = 0.0
            var commands: [String] = []
        }
        guard !samples.isEmpty else { return [] }
        var totals: [CgroupGroupKey: Totals] = [:]
        for groups in samples {
            for group in groups {
                let key = CgroupGroupKey(name: group.name, kind: group.kind, composeProject: group.composeProject)
                var total = totals[key] ?? Totals()
                let (cpu, memory) = (group.cpuCores ?? 0, Double(group.memoryBytes ?? 0))
                total.highestContainerCount = max(total.highestContainerCount, group.containerCount)
                total.cpuCores += cpu
                total.highestCPUCores = max(total.highestCPUCores, cpu)
                total.memoryBytes += memory
                total.highestMemoryBytes = max(total.highestMemoryBytes, memory)
                if total.commands.isEmpty { total.commands = group.commands }
                totals[key] = total
            }
        }
        let count = Double(samples.count)
        return totals.map { key, total in
            HourlyCgroupGroup(
                key: key,
                highestContainerCount: total.highestContainerCount,
                averageCPUCores: total.cpuCores / count,
                highestCPUCores: total.highestCPUCores,
                averageMemoryBytes: total.memoryBytes / count,
                highestMemoryBytes: total.highestMemoryBytes,
                commands: total.commands
            )
        }
    }

    /// The top groups by average CPU and by average memory, each once. Ties are broken by name, so the
    /// same hour always keeps the same groups.
    static func top(_ groups: [HourlyCgroupGroup]) -> [HourlyCgroupGroup] {
        let name = { (group: HourlyCgroupGroup) in [group.key.composeProject ?? "", group.key.name] }
        let byCPU = groups.sorted { ($0.averageCPUCores, name($1).joined()) > ($1.averageCPUCores, name($0).joined()) }
        let byMemory = groups.sorted { ($0.averageMemoryBytes, name($1).joined()) > ($1.averageMemoryBytes, name($0).joined()) }
        var kept: [HourlyCgroupGroup] = []
        for group in byCPU.prefix(topCountByEachMeasure) + byMemory.prefix(topCountByEachMeasure) where !kept.contains(group) {
            kept.append(group)
        }
        return kept
    }

    private static func sortedByCPU(_ groups: [CgroupGroupFigures]) -> [CgroupGroupFigures] {
        groups.sorted { ($0.cpuCores ?? 0, $0.memoryBytes ?? 0) > ($1.cpuCores ?? 0, $1.memoryBytes ?? 0) }
    }

    /// Nil only when every value is missing.
    private static func total(_ values: [Double?]) -> Double? {
        let present = values.compactMap(\.self)
        return present.isEmpty ? nil : present.reduce(0, +)
    }
}

/// A sample's containers and services as `cgroupTenSeconds` keeps them, by container ID.
struct StoredCgroupSample {
    let startsAt: Int64
    let containers: CgroupFigures?
    let services: CgroupFigures?

    init(row: Row) throws {
        startsAt = row["startsAt"]
        containers = try (row["containers"] as Data?).map { try ProcessGroupStorage.decode(CgroupFigures.self, from: $0) }
        services = try (row["services"] as Data?).map { try ProcessGroupStorage.decode(CgroupFigures.self, from: $0) }
    }

    /// Containers by group, with the names Hive knows now.
    func grouped(names: [String: ContainerName]) -> (containers: [CgroupGroupFigures], services: [CgroupGroupFigures]) {
        (containers.map { CgroupGrouping.containers($0, names: names) } ?? [], services.map(CgroupGrouping.services) ?? [])
    }
}

/// An hour's busiest container groups and services as `cgroupHour` keeps them.
struct StoredCgroupHour {
    let startsAt: Int64
    let sampleCount: Int
    let containers: [HourlyCgroupGroup]
    let services: [HourlyCgroupGroup]

    init(row: Row) throws {
        startsAt = row["startsAt"]
        sampleCount = row["sampleCount"]
        containers = try ProcessGroupStorage.decode([HourlyCgroupGroup].self, from: row["containers"])
        services = try ProcessGroupStorage.decode([HourlyCgroupGroup].self, from: row["services"])
    }
}

extension CgroupGrouping {
    /// Hours' groups put together, each hour weighted by its samples, an hour a group is missing from
    /// counting as nothing.
    static func combined(hours: [(sampleCount: Int, groups: [HourlyCgroupGroup])]) -> [HourlyCgroupGroup] {
        let samples = Double(hours.reduce(0) { $0 + $1.sampleCount })
        guard samples > 0 else { return [] }
        var totals: [CgroupGroupKey: HourlyCgroupGroup] = [:]
        var order: [CgroupGroupKey] = []
        for hour in hours {
            let weight = Double(hour.sampleCount) / samples
            for group in hour.groups {
                guard let total = totals[group.key] else {
                    order.append(group.key)
                    totals[group.key] = HourlyCgroupGroup(
                        key: group.key,
                        highestContainerCount: group.highestContainerCount,
                        averageCPUCores: group.averageCPUCores * weight,
                        highestCPUCores: group.highestCPUCores,
                        averageMemoryBytes: group.averageMemoryBytes * weight,
                        highestMemoryBytes: group.highestMemoryBytes,
                        commands: group.commands
                    )
                    continue
                }
                totals[group.key] = HourlyCgroupGroup(
                    key: group.key,
                    highestContainerCount: max(total.highestContainerCount, group.highestContainerCount),
                    averageCPUCores: total.averageCPUCores + group.averageCPUCores * weight,
                    highestCPUCores: max(total.highestCPUCores, group.highestCPUCores),
                    averageMemoryBytes: total.averageMemoryBytes + group.averageMemoryBytes * weight,
                    highestMemoryBytes: max(total.highestMemoryBytes, group.highestMemoryBytes),
                    commands: total.commands
                )
            }
        }
        return order.compactMap { totals[$0] }
    }
}
