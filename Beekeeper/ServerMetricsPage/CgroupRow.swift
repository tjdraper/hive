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
