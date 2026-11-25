import Foundation
import HiveKit

/// A server that stopped reporting, and when Hive last heard from it.
struct StoppedServer: Codable, Equatable, Sendable {
    let serverID: UUID
    let lastReportAt: Date
}

/// A filesystem's figures over their limits when its alert opened. Nil for one within its limit.
struct FilesystemReading: Codable, Equatable, Sendable {
    var usedShare: Double?
    var inodesUsedShare: Double?
    /// On the server's clock.
    var fillsAt: Int64?
}

/// Averages over `minutes` when the alert opened. Nil for one within its limit.
struct MemoryReading: Codable, Equatable, Sendable {
    var availableShare: Double?
    var swapInPagesPerSecond: Double?
    let minutes: Int
}

/// Averages over `minutes` when the alert opened. Nil for one within its limit.
struct CPUReading: Codable, Equatable, Sendable {
    var busyShare: Double?
    var stealShare: Double?
    var loadPerCore: Double?
    let minutes: Int
}

extension AlertFacts {
    /// Each server a metric alert is about, with how Beekeeper shows it. Empty for every other alert.
    var metricAlerts: [(serverID: UUID, alert: MetricAlert)] {
        switch self {
        case .stoppedReporting(let server):
            [(server.serverID, .stoppedReporting(since: server.lastReportAt, withOthers: false))]
        case .stoppedTogether(let servers):
            servers.map { ($0.serverID, .stoppedReporting(since: $0.lastReportAt, withOthers: true)) }
        case .clockAhead(let serverID, _):
            [(serverID, .clockAhead)]
        case .filesystemFilling(let serverID, let mountPoint, _):
            [(serverID, .filesystemFilling(mountPoint: mountPoint))]
        case .memoryShort(let serverID, _):
            [(serverID, .memoryShort)]
        case .cpuBusy(let serverID, _):
            [(serverID, .cpuBusy)]
        default:
            []
        }
    }
}
