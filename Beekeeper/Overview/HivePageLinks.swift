import SwiftUI

/// A row for the servers' metrics and each of the Hive's pages besides the Overview.
struct HivePageLinks: View {
    let onShowMetrics: () -> Void
    let onOpen: (HivePage) -> Void

    var body: some View {
        Section {
            row("Metrics", systemImage: "chart.xyaxis.line", action: onShowMetrics)
            ForEach(pages) { page in
                row(page.title, systemImage: page.systemImage) { onOpen(page) }
            }
        }
    }

    private func row(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var pages: [HivePage] {
        HivePage.allCases.filter { $0 != .overview }
    }
}

private extension HivePage {
    var systemImage: String {
        switch self {
        case .overview: "hexagon"
        case .jobLog: "list.bullet.rectangle"
        case .auditLog: "checklist"
        case .devices: "laptopcomputer.and.iphone"
        case .settings: "gearshape"
        }
    }
}
