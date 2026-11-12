import SwiftUI

struct DaemonSetupView: View {
    let updater: HiveUpdater

    @State private var store = DaemonSetupStore()
    @State private var isConfirmingRemoval = false

    private let settings = SystemSettingsNavigator()
    private let beekeeper = BeekeeperLauncher()

    var body: some View {
        Form {
            Section {
                DaemonStatusRow(state: store.state, isDevelopmentBuild: DaemonSetupStore.isDevelopmentBuild)
                stateAction
                if let failureMessage = store.failureMessage {
                    Text(failureMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("Full Disk Access") {
                Text(
                    "Hive needs Full Disk Access to write to the backup drive. "
                        + "Turn on Hive in the list. If it isn't there, add Hive from Applications."
                )
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Full Disk Access Settings") { settings.openFullDiskAccess() }
            }

            UpdatesSection(updater: updater)

            Section {
                HStack {
                    Button("Open Beekeeper") { beekeeper.open() }
                        .disabled(beekeeper.applicationURL == nil)
                    Spacer()
                    if canRemove {
                        Button("Remove Hive…", role: .destructive) { isConfirmingRemoval = true }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize()
        .task { await store.watch() }
        .confirmationDialog("Remove Hive?", isPresented: $isConfirmingRemoval) {
            Button("Remove Hive", role: .destructive) {
                Task { await store.remove() }
            }
        } message: {
            Text(
                "Hive stops running, and no more backups are made. "
                    + "Its settings and backups stay in place, and turning Hive on again picks them up."
            )
        }
    }

    @ViewBuilder private var stateAction: some View {
        switch store.state {
        case .notInstalled where !DaemonSetupStore.isDevelopmentBuild:
            Button("Turn On Hive") { store.install() }
                .buttonStyle(.borderedProminent)
        case .waitingForApproval:
            Button("Open Login Items Settings") { settings.openLoginItems() }
                .buttonStyle(.borderedProminent)
        default:
            EmptyView()
        }
    }

    private var canRemove: Bool {
        !DaemonSetupStore.isDevelopmentBuild && store.isRegistered
    }
}
