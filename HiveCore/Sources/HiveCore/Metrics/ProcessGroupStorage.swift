import Foundation
import ScoutProtocol

/// One process group over an hour, from the hour's samples (§6). A group outside a sample's top lists
/// counts as nothing in that sample, so averages are at least what's shown.
struct HourlyProcessGroup: Codable, Equatable, Sendable {
    let command: String
    let user: String
    let highestCount: Int
    let averageCPUCores: Double
    let highestCPUCores: Double
    let averageOwnMemoryBytes: UInt64
    let highestOwnMemoryBytes: UInt64
}

/// Process groups as stored: JSON compressed with LZFSE, since they're only ever read whole.
enum ProcessGroupStorage {
    static let hourlyTopCount = 10

    static func encode(_ value: some Encodable) throws -> Data {
        try (JSONEncoder().encode(value) as NSData).compressed(using: .lzfse) as Data
    }

    static func decode<Value: Decodable>(_: Value.Type, from data: Data) throws -> Value {
        try JSONDecoder().decode(Value.self, from: (data as NSData).decompressed(using: .lzfse) as Data)
    }

    /// The hour's top groups by average CPU and by average memory, each once.
    static func hourly(of samples: [[ProcessGroup]]) -> [HourlyProcessGroup] {
        struct Key: Hashable {
            let command: String
            let user: String
        }
        struct Totals {
            var highestCount = 0
            var cpuCores = 0.0
            var highestCPUCores = 0.0
            var ownMemoryBytes = 0.0
            var highestOwnMemoryBytes: UInt64 = 0
        }
        guard !samples.isEmpty else { return [] }
        var totals: [Key: Totals] = [:]
        for groups in samples {
            for group in groups {
                let key = Key(command: group.command, user: group.user)
                var total = totals[key] ?? Totals()
                total.highestCount = max(total.highestCount, group.count)
                total.cpuCores += group.cpuCores ?? 0
                total.highestCPUCores = max(total.highestCPUCores, group.cpuCores ?? 0)
                total.ownMemoryBytes += Double(group.ownMemoryBytes)
                total.highestOwnMemoryBytes = max(total.highestOwnMemoryBytes, group.ownMemoryBytes)
                totals[key] = total
            }
        }
        let count = Double(samples.count)
        let groups = totals.map { key, total in
            HourlyProcessGroup(
                command: key.command,
                user: key.user,
                highestCount: total.highestCount,
                averageCPUCores: total.cpuCores / count,
                highestCPUCores: total.highestCPUCores,
                averageOwnMemoryBytes: UInt64((total.ownMemoryBytes / count).rounded()),
                highestOwnMemoryBytes: total.highestOwnMemoryBytes
            )
        }
        // Ties are broken by name, so the same hour always keeps the same groups.
        let byName = { (left: HourlyProcessGroup, right: HourlyProcessGroup) in (left.command, left.user) < (right.command, right.user) }
        let byCPU = groups.sorted { $0.averageCPUCores != $1.averageCPUCores ? $0.averageCPUCores > $1.averageCPUCores : byName($0, $1) }
        let byMemory = groups.sorted {
            $0.averageOwnMemoryBytes != $1.averageOwnMemoryBytes ? $0.averageOwnMemoryBytes > $1.averageOwnMemoryBytes : byName($0, $1)
        }
        var kept: [HourlyProcessGroup] = []
        for group in byCPU.prefix(hourlyTopCount) + byMemory.prefix(hourlyTopCount) where !kept.contains(group) {
            kept.append(group)
        }
        return kept
    }
}
