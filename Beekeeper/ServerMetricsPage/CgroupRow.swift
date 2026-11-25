import HiveKit
import SwiftUI

/// A group of containers, one container or a systemd service as a list shows it, from a sample or from
/// an hour's busiest. Nonisolated so a table can sort by its key paths.
nonisolated struct CgroupRow: Identifiable, Sendable {
    enum Subject: Hashable, Sendable {
        case group(name: String, composeProject: String?)
        case container(id: String)
        case service(String)
    }

    let id: Subject
    let name: String
    /// The group whose color it has on the charts.
    let groupName: String
    let composeProject: String?
    /// What it is, or for a container Hive couldn't name, what it runs.
    let detail: String
    let containerCount: Int?
    let cpuCores: Double?
    let highestCPUCores: Double?
    let memoryBytes: UInt64?
    let highestMemoryBytes: UInt64?
    let processes: Int?

    /// For sorting, with one missing its CPU, as in a Scout's first sample, last.
    var cpuOrder: Double {
        cpuCores ?? -1
    }

    var memoryOrder: Double {
        memoryBytes.map(Double.init) ?? -1
    }

    var processOrder: Int {
        processes ?? -1
    }

    var cpuText: String {
        guard let cpuCores else { return "—" }
        let average = ProcessRow.share(cpuCores)
        guard let highestCPUCores else { return average }
        return "\(average), up to \(ProcessRow.share(highestCPUCores))"
    }

    /// Missing where the server doesn't account for its containers' memory.
    var memoryText: String {
        guard let memoryBytes else { return "—" }
        let average = Int64(clamping: memoryBytes).formatted(.byteCount(style: .memory))
        guard let highestMemoryBytes else { return average }
        return "\(average), up to \(Int64(clamping: highestMemoryBytes).formatted(.byteCount(style: .memory)))"
    }

    /// Whether `process` runs in this group, container or service.
    func holds(_ process: ProcessRow) -> Bool {
        switch id {
        case .group(let name, let composeProject):
            process.place?.containerGroup == name && process.place?.composeProject == composeProject
        case .container(let id):
            process.place?.containerID == id
        case .service(let name):
            process.place?.service == name
        }
    }

    static func groups(_ groups: [CgroupGroupFigures]) -> [CgroupRow] {
        groups.map { group in
            CgroupRow(
                id: .group(name: group.name, composeProject: group.composeProject),
                name: CgroupHistory.name(group.name, composeProject: group.composeProject),
                groupName: group.name,
                composeProject: group.composeProject,
                detail: detail(of: group),
                containerCount: group.containerCount,
                cpuCores: group.cpuCores,
                highestCPUCores: group.highestCPUCores,
                memoryBytes: group.memoryBytes,
                highestMemoryBytes: group.highestMemoryBytes,
                processes: group.processes
            )
        }
    }

    /// Each container in the groups, which only a sample holds.
    static func containers(_ groups: [CgroupGroupFigures]) -> [CgroupRow] {
        groups.flatMap { group in
            group.containers.map { container in
                CgroupRow(
                    id: .container(id: container.id),
                    name: container.name ?? String(container.id.prefix(12)),
                    groupName: group.name,
                    composeProject: group.composeProject,
                    detail: group.kind == .unnamed
                        ? container.commands.joined(separator: ", ")
                        : CgroupHistory.name(group.name, composeProject: group.composeProject),
                    containerCount: nil,
                    cpuCores: container.cpuCores,
                    highestCPUCores: nil,
                    memoryBytes: container.memoryBytes,
                    highestMemoryBytes: nil,
                    processes: container.processes
                )
            }
        }
    }

    static func services(_ services: [CgroupGroupFigures]) -> [CgroupRow] {
        services.map { service in
            CgroupRow(
                id: .service(service.name),
                name: service.name,
                groupName: service.name,
                composeProject: nil,
                detail: "",
                containerCount: nil,
                cpuCores: service.cpuCores,
                highestCPUCores: service.highestCPUCores,
                memoryBytes: service.memoryBytes,
                highestMemoryBytes: service.highestMemoryBytes,
                processes: service.processes
            )
        }
    }

    private static func detail(of group: CgroupGroupFigures) -> String {
        switch group.kind {
        case .swarmService: "Swarm service"
        case .composeService: "Compose service"
        case .container: "Container"
        case .unnamed: group.commands.joined(separator: ", ")
        case nil: ""
        }
    }
}

extension CgroupMoment {
    /// The container groups, each container, or the services. Only a sample holds each container.
    func rows(of kind: ContainersPage.Kind, eachContainer: Bool) -> [CgroupRow] {
        switch (self, kind) {
        case (.sample(_, _, _, let containers, _), .containers) where eachContainer:
            CgroupRow.containers(containers)
        case (.sample(_, _, _, let containers, _), .containers), (.hour(_, let containers, _), .containers):
            CgroupRow.groups(containers)
        case (.sample(_, _, _, _, let services), .services), (.hour(_, _, let services), .services):
            CgroupRow.services(services)
        case (.notKept, _):
            []
        }
    }

    /// How many are running beside those shown. Scout sends only the busiest, so a group holds only
    /// those of its containers among them.
    func note(of kind: ContainersPage.Kind) -> String {
        switch (self, kind) {
        case (.sample(_, let containerCount, _, let containers, _), .containers):
            let shown = containers.reduce(0) { $0 + $1.containerCount }
            guard shown < containerCount else { return "\(containerCount) running." }
            return "\(containerCount) running. Scout sends the busiest \(shown), so a group counts only those of its containers."
        case (.sample(_, _, let serviceCount, _, let services), .services):
            let shown = services.count < serviceCount
                ? "\(serviceCount) running, the busiest \(services.count) shown. "
                : "\(serviceCount) running. "
            return shown + "A service's CPU includes work that started and finished between samples, such as cron jobs."
        case (.hour, _):
            return "Single samples are kept for a day, and each hour's busiest for 90 days."
        case (.notKept, _):
            return " "
        }
    }
}

/// A container group, container or service as a list's row, with the one of its CPU and memory the list
/// is in order of in bold, and its color on the charts where it has one.
struct CgroupListRow: View {
    let row: CgroupRow
    var order = MomentProcesses.Order.cpu
    var color: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let color {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 9, height: 9)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.containerCount.map { $0 > 1 ? "\(row.name) ×\($0)" : row.name } ?? row.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(row.cpuText) CPU")
                    .fontWeight(order == .cpu ? .semibold : .regular)
                Text(row.memoryText)
                    .font(.caption)
                    .fontWeight(order == .memory ? .semibold : .regular)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
