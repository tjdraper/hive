import SwiftUI

struct DaemonStatusRow: View {
    let state: DaemonSetupStore.State
    let isDevelopmentBuild: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.caption)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var title: String {
        switch state {
        case .checking: "Checking…"
        case .notInstalled: "Hive is off"
        case .waitingForApproval: "Waiting for approval"
        case .notRunning: isDevelopmentBuild ? "The development daemon isn't running" : "Approved, but not running"
        case .running: isDevelopmentBuild ? "The development daemon is running" : "Running"
        case .missingFromBundle: "This copy of Hive is incomplete"
        case .notOwnedByRoot: "Hive needs to be installed by an administrator"
        }
    }

    private var detail: String {
        switch state {
        case .checking:
            ""
        case .notInstalled:
            "Turn Hive on to run backups in the background, even while nobody is logged in."
        case .waitingForApproval:
            "Allow Hive in System Settings › General › Login Items."
        case .notRunning:
            isDevelopmentBuild
                ? "Scripts/install-test-build.sh --mac starts it."
                : "macOS starts Hive again within a few seconds. If it stays stopped, the system log says why."
        case .running:
            isDevelopmentBuild
                ? "It runs as a user agent, with its own data, apart from an installed Hive."
                : "Hive runs in the background and starts with the Mac."
        case .missingFromBundle:
            "Its daemon is missing. Install Hive again."
        case .notOwnedByRoot:
            "Hive starts with administrator rights, so only the system may be able to change it. Install it with Hive's installer."
        }
    }

    private var color: Color {
        switch state {
        case .checking, .notInstalled: .secondary
        case .waitingForApproval, .notRunning: .orange
        case .running: .green
        case .missingFromBundle, .notOwnedByRoot: .red
        }
    }
}
