import HiveKit
import SwiftUI

/// A group of processes as a list shows it, from a sample or from an hour's busiest. Nonisolated so a
/// table can sort by its key paths.
nonisolated struct ProcessRow: Identifiable, Sendable {
    let command: String
    let user: String
    let count: Int
    let cpuCores: Double?
    let memoryBytes: UInt64
    /// The hour's highest, beside its average.
    var highestCPUCores: Double?
    var highestMemoryBytes: UInt64?

    var id: String {
        "\(command) \(user)"
    }

    /// For sorting, with a group missing its CPU, as in a Scout's first sample, last.
    var cpuOrder: Double {
        cpuCores ?? -1
    }

    var name: String {
        count > 1 ? "\(command) ×\(count)" : command
    }

    /// A share of one core, so 2 busy cores read 200%.
    var cpuText: String {
        guard let cpuCores else { return "—" }
        let average = Self.share(cpuCores)
        guard let highestCPUCores else { return average }
        return "\(average), up to \(Self.share(highestCPUCores))"
    }

    var memoryText: String {
        let average = Int64(clamping: memoryBytes).formatted(.byteCount(style: .memory))
        guard let highestMemoryBytes else { return average }
        return "\(average), up to \(Int64(clamping: highestMemoryBytes).formatted(.byteCount(style: .memory)))"
    }

    static func rows(_ moment: ProcessMoment) -> [ProcessRow] {
        switch moment {
        case .sample(_, let groups):
            groups.map {
                ProcessRow(command: $0.command, user: $0.user, count: $0.count, cpuCores: $0.cpuCores, memoryBytes: $0.ownMemoryBytes)
            }
        case .hour(_, let groups):
            groups.map {
                ProcessRow(
                    command: $0.command,
                    user: $0.user,
                    count: $0.highestCount,
                    cpuCores: $0.averageCPUCores,
                    memoryBytes: $0.averageOwnMemoryBytes,
                    highestCPUCores: $0.highestCPUCores,
                    highestMemoryBytes: $0.highestOwnMemoryBytes
                )
            }
        case .notKept:
            []
        }
    }

    /// Most groups use well under 1% of a core, which whole percents would all show as 0.
    private static func share(_ cores: Double) -> String {
        cores.formatted(.percent.precision(.fractionLength(cores < 0.1 ? 1 : 0)))
    }

    static func time(_ second: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(second)).formatted(date: .abbreviated, time: .standard)
    }
}
