import Foundation
import HiveKit

/// A figure on a server's card that's past its alert limit. The limits are §8's defaults in the server
/// metrics plan, fixed until each server has its own (C1). Steal and swapping in need figures the
/// dashboard doesn't have, so they wait for C1 too.
enum MetricsConcern: Hashable {
    case cpu
    case memory
    case disk
    case load

    private static let busiestCPU = 0.9
    private static let cpuMinutes = 15
    private static let fullestMemory = 0.9
    private static let memoryMinutes = 10
    private static let fullestDisk = 0.9
    private static let heaviestLoadPerCore = 2.0

    static func concerns(in latest: ServerMetricsLatest?, lastHour: [MetricsSparkPoint]) -> Set<MetricsConcern> {
        var concerns: Set<MetricsConcern> = []
        if isOver(busiestCPU, every: \.cpuBusy, forLast: cpuMinutes, of: lastHour) { concerns.insert(.cpu) }
        if isOver(fullestMemory, every: \.memoryUsed, forLast: memoryMinutes, of: lastHour) { concerns.insert(.memory) }
        if let filesystem = latest?.fullestFilesystem, filesystem.usedShare > fullestDisk { concerns.insert(.disk) }
        // The 15-minute load is already an average over the limit's duration.
        if let load = latest?.load, let cores = latest?.cores, cores > 0,
           load.fifteenMinutes > heaviestLoadPerCore * Double(cores) {
            concerns.insert(.load)
        }
        return concerns
    }

    /// Every minute of the newest `minutes` was kept and over `limit`, so a short spike doesn't count.
    private static func isOver(
        _ limit: Double,
        every figure: KeyPath<MetricsSparkPoint, Double?>,
        forLast minutes: Int,
        of points: [MetricsSparkPoint]
    ) -> Bool {
        guard let newest = points.last else { return false }
        let recent = points.filter { $0.startsAt > newest.startsAt - Int64(minutes * 60) }
        return recent.count >= minutes && recent.allSatisfy { ($0[keyPath: figure] ?? 0) > limit }
    }
}
