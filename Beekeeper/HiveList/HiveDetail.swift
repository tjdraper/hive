import HiveKit
import SwiftUI

struct HiveDetail: View {
    let hive: KnownHive
    let link: HiveLink
    let servers: ServerList
    let recovery: RecoveryFileCopies
    @Binding var page: HivePage
    @Binding var selection: SidebarItem?
    let onAddServer: () -> Void

    @Environment(HiveListStore.self) private var store
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        #if os(iOS)
        if sizeClass == .compact {
            compactPage
        } else {
            tabbedPage
        }
        #else
        tabbedPage
        #endif
    }

    private var tabbedPage: some View {
        HiveConnectionGate(hive: hive, link: link) {
            pageView(page)
        }
        .navigationTitle(hive.name)
        .locationPath([LocationPath.Part(title: hive.name, systemImage: "hexagon")], besideTabs: true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Page", selection: $page) {
                    ForEach(HivePage.allCases) { page in
                        Text(page.title).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    #if os(iOS)
    /// At iPhone width the Overview is the Hive's page, and the others open from rows at its end.
    private var compactPage: some View {
        HiveConnectionGate(hive: hive, link: link) {
            overview { page = $0 }
        }
        .navigationTitle(hive.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Server", systemImage: "plus", action: onAddServer)
                    .disabled(link.status != .connected)
            }
        }
        .navigationDestination(item: openPage) { page in
            HiveConnectionGate(hive: hive, link: link) {
                pageView(page)
            }
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// The page pushed over the Overview, which is nil for the Overview itself.
    private var openPage: Binding<HivePage?> {
        Binding {
            page == .overview ? nil : page
        } set: {
            page = $0 ?? .overview
        }
    }
    #endif

    private func overview(onOpenPage: ((HivePage) -> Void)?) -> some View {
        HiveOverviewView(
            hive: hive,
            link: link,
            servers: servers,
            recovery: recovery,
            onAddServer: onAddServer,
            onOpenSettings: { page = .settings },
            onOpenPage: onOpenPage,
            onSelectServer: { selection = .server(hiveID: hive.id, serverID: $0) },
            onRestored: restored
        )
    }

    @ViewBuilder
    private func pageView(_ page: HivePage) -> some View {
        switch page {
        case .overview: overview(onOpenPage: nil)
        case .jobLog: JobLogView(link: link, servers: servers)
        case .devices: DeviceListView(hive: hive, link: link)
        case .auditLog: AuditLogView(link: link)
        case .settings: HiveSettingsView(hive: hive, link: link, recovery: recovery)
        }
    }
}

extension HiveDetail {
    /// The restored Hive takes this one's place in the list, under the restored Hive's ID.
    private func restored(_ outcome: RestoreOutcome) {
        #if os(macOS)
        if store.adoptRestoredHive(hive.id, as: outcome) {
            page = .overview
            selection = .hive(outcome.hiveID)
        }
        #endif
    }
}

/// Shows `content` while Beekeeper is signed in to the Hive, and otherwise why it isn't.
struct HiveConnectionGate<Content: View>: View {
    let hive: KnownHive
    let link: HiveLink
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch link.status {
        case .connected:
            content()
        case .connecting:
            ProgressView("Connecting…")
                .task { await link.refresh() }
        case .pairingAgain:
            ProgressView("Pairing again with the Hive's new identity…")
        case .restarting:
            ProgressView("Waiting for the restored Hive to start…")
        default:
            HiveProblemView(hive: hive, link: link)
        }
    }
}

/// Why Beekeeper isn't showing the Hive, and what can be done about it.
private struct HiveProblemView: View {
    let hive: KnownHive
    let link: HiveLink

    @Environment(HiveListStore.self) private var store
    @Environment(\.addHive) private var addHive
    #if os(macOS)
    @Environment(BeekeeperUpdater.self) private var updater
    #endif
    @State private var isConfirmingRemoval = false

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(explanation)
        } actions: {
            actions
        }
        .confirmationDialog("Remove \(hive.name) from Beekeeper?", isPresented: $isConfirmingRemoval) {
            Button("Remove", role: .destructive) { store.remove(hive.id) }
        } message: {
            Text("This device is no longer paired with it, so Beekeeper can't manage it until it pairs again.")
        }
    }

    @ViewBuilder private var actions: some View {
        switch link.status {
        case .offline, .lockedOut, .failed:
            Button("Try Again") { Task { await link.refresh() } }
        case .identityChanged, .notRecognized, .notPaired:
            #if os(macOS)
            if hive.isOnThisMac {
                PairWithThisMacButton(title: "Pair Again") { _ in
                    // The link reconnects, and the page shows once it's signed in.
                }
            }
            #endif
            if !hive.isOnThisMac {
                Button("Pair Again with a Code…") { addHive?() }
            }
            if link.status != .identityChanged || !hive.isOnThisMac {
                Button("Remove from Beekeeper…") { isConfirmingRemoval = true }
            }
        case .needsUpdate(.hive):
            #if os(macOS)
            if hive.isOnThisMac {
                OpenHiveButton()
            }
            #endif
        case .needsUpdate(.beekeeper):
            #if os(macOS)
            if updater.updatesItself {
                Button("Check for Updates…") { updater.checkForUpdates() }
            }
            #endif
        case .connecting, .pairingAgain, .restarting, .connected:
            EmptyView()
        }
    }

    private var title: String {
        switch link.status {
        case .offline: "Can't Reach This Hive"
        case .identityChanged: "This Hive's Identity Has Changed"
        case .notRecognized: "This Hive Doesn't Recognize This Device"
        case .notPaired: "Not Paired"
        case .lockedOut: "Too Many Failed Sign-Ins"
        case .needsUpdate(.hive): "Update Hive"
        case .needsUpdate(.beekeeper): "Update Beekeeper"
        case .failed: "Something Went Wrong"
        case .connecting, .pairingAgain, .restarting, .connected: ""
        }
    }

    private var systemImage: String {
        switch link.status {
        case .offline: "wifi.slash"
        case .identityChanged: "exclamationmark.shield"
        case .notRecognized, .notPaired: "person.crop.circle.badge.questionmark"
        case .lockedOut: "lock"
        case .needsUpdate: "arrow.down.circle"
        case .failed, .connecting, .pairingAgain, .restarting, .connected: "exclamationmark.triangle"
        }
    }

    private var explanation: String {
        switch link.status {
        case .offline:
            "Check that the Hive's Mac is on and Hive is running."
        case .identityChanged where hive.isOnThisMac:
            "It showed a different key from the one this device paired with. Beekeeper won't connect to it until you pair again."
        case .identityChanged:
            "It showed a different key from the one this device paired with. Beekeeper won't connect to it until you pair "
                + "again, with a code from a device that's paired with it now."
        case .notRecognized where hive.isOnThisMac:
            "This device may have been revoked from another one. Pair again to manage this Hive."
        case .notRecognized:
            "This device may have been revoked from another one. Pair again with a code from a device that's still paired."
        case .notPaired:
            "This device isn't paired with this Hive any more."
        case .lockedOut:
            "The Hive is turning this device away for now. Try again in 15 minutes."
        case .needsUpdate(.hive):
            "This Hive is too old to work with this Beekeeper."
        case .needsUpdate(.beekeeper):
            "This Beekeeper is too old to work with this Hive."
        case .failed(let message):
            message
        case .connecting, .pairingAgain, .restarting, .connected:
            ""
        }
    }
}
