import Foundation

/// The warnings Hive emails before a device's build expires (§16), in the order they go out.
enum BuildExpiryWarning: String, Codable, Comparable, Sendable, CaseIterable {
    case twoWeeks
    case threeDays

    var leadTime: TimeInterval {
        switch self {
        case .twoWeeks: 14 * 24 * 60 * 60
        case .threeDays: 3 * 24 * 60 * 60
        }
    }

    /// The latest warning due for a build expiring at `expiresAt`, or nil when none is yet, or the build
    /// has already expired. A build first reported with three days left gets only the last one.
    static func due(expiresAt: Date, at date: Date) -> BuildExpiryWarning? {
        guard expiresAt > date else { return nil }
        return allCases.last { expiresAt.timeIntervalSince(date) <= $0.leadTime }
    }

    static func < (lhs: BuildExpiryWarning, rhs: BuildExpiryWarning) -> Bool {
        lhs.leadTime > rhs.leadTime
    }
}
