import SwiftUI

struct HiveSidebar: View {
    @Environment(HiveListStore.self) private var store
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            ForEach(store.hives) { hive in
                Section {
                    ForEach(HivePage.allCases) { page in
                        NavigationLink(value: SidebarItem(hiveID: hive.id, page: page)) {
                            Label(page.title, systemImage: page.systemImage)
                        }
                    }
                } header: {
                    HiveSidebarHeader(hive: hive, status: store.link(for: hive.id)?.status ?? .notPaired)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct HiveSidebarHeader: View {
    let hive: KnownHive
    let status: HiveLink.Status

    var body: some View {
        HStack(spacing: 6) {
            Text(hive.name)
                .lineLimit(1)
            Spacer()
            HiveStatusBadge(status: status)
        }
        // macOS insets sidebar rows on both sides but section headers only on the leading one.
        .padding(.trailing, 10)
    }
}

/// A dot and a word for how the Hive's connection stands.
struct HiveStatusBadge: View {
    let status: HiveLink.Status

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch status {
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .offline: "Offline"
        case .identityChanged: "Identity changed"
        case .notRecognized, .notPaired: "Not paired"
        case .lockedOut: "Locked out"
        case .needsUpdate: "Needs update"
        case .failed: "Problem"
        }
    }

    private var color: Color {
        switch status {
        case .connected: .green
        case .connecting, .offline: .secondary
        case .identityChanged, .notRecognized, .failed: .red
        case .notPaired, .lockedOut, .needsUpdate: .orange
        }
    }
}
