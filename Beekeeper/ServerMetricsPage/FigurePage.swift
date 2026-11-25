import SwiftUI

/// A page of one kind of a server's figures, reached from its metrics page.
enum FigurePage: Hashable {
    case processes
    case cgroups(ContainersPage.Kind)
    case filesystem(mountPoint: String)
}

/// Where a page of a server's figures sits: its Hive, the dashboard and the server's metrics page.
struct MetricsPagePath {
    let hiveName: String
    let source: MetricsSource
    let onShowHive: () -> Void
    let onShowDashboard: () -> Void
    let onShowServer: () -> Void

    func parts(_ title: String, systemImage: String) -> [LocationPath.Part] {
        [
            LocationPath.Part(title: hiveName, systemImage: "hexagon", action: onShowHive),
            LocationPath.Part(title: "Metrics", systemImage: "chart.xyaxis.line", action: onShowDashboard),
            LocationPath.Part(title: source.name, systemImage: source.systemImage, action: onShowServer),
            LocationPath.Part(title: title, systemImage: systemImage),
        ]
    }
}
