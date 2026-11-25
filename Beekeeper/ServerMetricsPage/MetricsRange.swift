import Foundation

/// How far back a server's charts reach. Every range ends now.
enum MetricsRange: String, CaseIterable, Identifiable {
    case hour
    case sixHours
    case day
    case week
    case month
    case year

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .hour: "Hour"
        case .sixHours: "6 Hours"
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    var seconds: Int64 {
        switch self {
        case .hour: 3_600
        case .sixHours: 6 * 3_600
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .year: 365 * 86_400
        }
    }

    /// An hour's buckets are single samples, so it's read again with each one. Longer ranges' newest
    /// bucket fills more slowly.
    var refreshInterval: Duration {
        self == .hour ? .seconds(10) : .seconds(60)
    }
}
