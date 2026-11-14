import HiveKit
import SwiftUI

/// The build a device last reported, such as “2026.3 (12), TestFlight”.
struct DeviceBuildLabel: View {
    let build: BeekeeperBuild?

    var body: some View {
        if let build {
            Text("\(build.version) (\(build.build)), \(build.distribution.title)")
        } else {
            Text("Not reported").foregroundStyle(.secondary)
        }
    }
}

/// When a device's build stops opening, marked once it has or soon will.
struct DeviceExpiryLabel: View {
    /// Matches Hive's first warning.
    private static let soon: TimeInterval = 14 * 24 * 60 * 60

    let build: BeekeeperBuild?
    /// Says what the date is, for where there's no Expires heading above it.
    var isLabeled = false

    var body: some View {
        if let expiresAt = build?.expiresAt {
            let date = expiresAt.formatted(date: .abbreviated, time: .omitted)
            let remaining = expiresAt.timeIntervalSinceNow
            if remaining <= 0 {
                Label("Expired \(date)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if remaining <= Self.soon {
                Label(isLabeled ? "Expires \(date)" : date, systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            } else {
                Text(isLabeled ? "Expires \(date)" : date)
            }
        } else if build?.platform == .mac {
            Text("Never").foregroundStyle(.secondary)
        } else {
            Text("Unknown").foregroundStyle(.secondary)
        }
    }
}

extension BuildDistribution {
    var title: String {
        switch self {
        case .developerID: "Developer ID"
        case .testFlight: "TestFlight"
        case .adHoc: "Ad Hoc"
        case .development: "Development"
        }
    }
}
