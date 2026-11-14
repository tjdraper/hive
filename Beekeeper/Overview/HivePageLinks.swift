import SwiftUI

/// A row for each of the Hive's pages besides the Overview.
struct HivePageLinks: View {
    let onOpen: (HivePage) -> Void

    var body: some View {
        Section {
            ForEach(pages) { page in
                Button { onOpen(page) } label: {
                    HStack {
                        Label(page.title, systemImage: page.systemImage)
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
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
