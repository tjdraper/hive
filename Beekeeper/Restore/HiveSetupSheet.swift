import HiveKit
import SwiftUI

/// Setting up a Hive just installed on this Mac: as a new Hive, starting with its recovery key, or as a
/// Hive brought back from one of its recovery files.
struct HiveSetupSheet: View {
    let hive: KnownHive
    let link: HiveLink
    let onKeySaved: (RecoveryKeyState) -> Void
    let onRestored: (RestoreOutcome) -> Void

    private enum Choice {
        case newHive
        case restore
    }

    @Environment(\.dismiss) private var dismiss
    @State private var choice: Choice?

    var body: some View {
        switch choice {
        case .newHive:
            RecoveryKeySheet(hiveName: hive.name, link: link, onSaved: onKeySaved)
        case .restore:
            RestoreSheet(hive: hive, link: link, onRestored: onRestored)
        case nil:
            choices
        }
    }

    private var choices: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Set Up “\(hive.name)”")
                    .font(.title2.bold())
                Text("Start a new Hive, or bring back one whose Mac was lost or replaced.")
                    .foregroundStyle(.secondary)
                ChoiceRow(
                    title: "A New Hive",
                    detail: "Starts with a recovery key to save, then servers to back up.",
                    systemImage: "sparkles",
                    action: "Set Up New Hive…"
                ) { choice = .newHive }
                ChoiceRow(
                    title: "A Hive Whose Mac Was Lost or Replaced",
                    detail: "Brings back its servers, jobs, passwords and SSH keys from a recovery file and its recovery key.",
                    systemImage: "clock.arrow.circlepath",
                    action: "Restore…"
                ) { choice = .restore }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            HStack {
                Spacer()
                Button("Later", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 560, height: 330)
    }
}

private struct ChoiceRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: String
    let perform: () -> Void

    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action, action: perform)
            }
            .padding(6)
        }
    }
}
