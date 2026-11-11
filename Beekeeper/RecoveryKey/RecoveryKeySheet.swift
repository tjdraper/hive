import HiveKit
import SwiftUI

/// Shows a new recovery key once, and saves it with the Hive when the person says they've saved it.
struct RecoveryKeySheet: View {
    let hiveName: String
    let link: HiveLink
    /// In place of the Hive's old key.
    var isReplacing = false
    let onSaved: (RecoveryKeyState) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var setup = RecoveryKeySetup()
    @State private var isCopied = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text(isReplacing ? "Save the New Recovery Key for “\(hiveName)”" : "Save the Recovery Key for “\(hiveName)”")
                    .font(.title2.bold())
                Text(
                    "If this Hive's Mac is lost, this key brings the Hive back on another Mac with its servers, jobs, "
                        + "passwords and SSH keys. Save it in your password manager."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if isReplacing {
                    Text(
                        "Recovery files in Mac backups still open with the old key. If it may have leaked, give each server "
                            + "a new SSH key and change the database and email passwords, since those files hold them."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                RecoveryKeyCode(groups: setup.key.groups)

                HStack {
                    Button(isCopied ? "Copied" : "Copy Key", systemImage: isCopied ? "checkmark" : "doc.on.doc") {
                        RecoveryKeyPasteboard.copy(setup.key.code)
                        isCopied = true
                    }
                    Spacer()
                }

                Label(
                    "It's shown only this once. Hive keeps only the half that writes recovery files, so nobody can show it again.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

                if let failure = setup.failure {
                    Text(failure)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("I've Saved It") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(setup.isSaving)
            }
            .padding()
        }
        .frame(width: 560, height: isReplacing ? 480 : 420)
        .interactiveDismissDisabled()
    }

    private func save() async {
        let reason = isReplacing
            ? "replace the recovery key for “\(hiveName)”, so new recovery files open only with the new one"
            : "save the recovery key for “\(hiveName)”"
        guard let state = await setup.save(on: link, reason: reason) else { return }
        onSaved(state)
        dismiss()
    }
}

/// The key's groups, large enough to copy out by hand without mistaking one character for another.
private struct RecoveryKeyCode: View {
    let groups: [String]

    var body: some View {
        Text(groups.joined(separator: "-"))
            .font(.system(size: 22, weight: .medium, design: .monospaced))
            .textSelection(.enabled)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(.background.secondary, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            .accessibilityLabel(Text("Recovery key"))
    }
}
