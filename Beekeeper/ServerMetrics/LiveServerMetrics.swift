import Foundation
import HiveKit
import Observation

/// Each of one Hive's servers' newest figures, as live updates bring them.
@Observable
final class LiveServerMetrics {
    private(set) var latest: [UUID: ServerMetricsLatest] = [:]

    /// Ignores figures older than those already shown, such as from a response that ended late.
    func receive(_ figures: ServerMetricsLatest) {
        if let current = latest[figures.serverID], current.takenAt >= figures.takenAt { return }
        latest[figures.serverID] = figures
    }
}
