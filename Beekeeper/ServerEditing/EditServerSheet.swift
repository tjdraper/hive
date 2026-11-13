import HiveKit
import SwiftUI

/// Changing a server's name, where Hive connects, or its quota. Changing where Hive connects or lowering
/// the quota asks for Touch ID or the password on Save.
struct EditServerSheet: View {
    let servers: ServerList
    let server: Server

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ServerDraft
    @State private var problems = ServerFieldProblems()
    @State private var isSaving = false
    @State private var failure: String?
    @State private var space: ServerSpace?
    @State private var quotaEstimate: RemovalEstimate?

    init(servers: ServerList, server: Server) {
        self.servers = servers
        self.server = server
        _draft = State(initialValue: server.draft)
    }

    var body: some View {
        SheetLayout(
            title: "Edit “\(server.name)”",
            cancel: SheetButton(title: "Cancel") { dismiss() },
            confirm: SheetButton(title: "Save", isDisabled: draft == server.draft || !draft.isComplete || isSaving) {
                Task { await save() }
            }
        ) {
            Form {
                ServerFields(draft: $draft, problems: problems)
                if changesConnection {
                    Section {
                        Label(
                            "Changing the host, port or SSH user clears the database passwords of this server's jobs, "
                                + "and its host key has to be checked and confirmed again before Hive connects.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }
                QuotaField(
                    quotaBytes: $draft.quotaBytes,
                    saved: server.quotaBytes,
                    space: space,
                    estimate: quotaEstimate,
                    problem: problems[.quota]
                )
                if let failure {
                    Text(failure)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
        }
        .macSheetSize(width: 560, height: 560)
        .task { space = try? await servers.space(of: server.id) }
        .task(id: draft.quotaBytes) { await estimateQuota() }
    }

    private var lowersQuota: Bool {
        QuotaField.isLowered(from: server.quotaBytes, to: draft.quotaBytes)
    }

    /// Once the amount stops changing.
    private func estimateQuota() async {
        quotaEstimate = nil
        guard lowersQuota else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        quotaEstimate = try? await servers.estimate(quotaBytes: draft.quotaBytes, of: server.id)
    }

    /// What Touch ID or the password prompt says, or nil when the change needs no confirming.
    private var confirmationReason: String? {
        var parts: [String] = []
        if changesConnection { parts.append("change where Hive connects to “\(server.name)”") }
        if lowersQuota {
            let deleting = switch quotaEstimate?.snapshotCount {
            case nil: ", which deletes snapshots"
            case 0: ""
            case .some(let count): ", deleting up to \(SnapshotCount(count))"
            }
            parts.append("lower the quota of “\(server.name)”\(deleting)")
        }
        return parts.isEmpty ? nil : parts.formatted(.list(type: .and))
    }

    /// Hive lowercases the host and trims the user, so compare them as it will store them.
    private var changesConnection: Bool {
        let connection = draft.connection
        return connection.host.trimmingCharacters(in: .whitespaces).lowercased() != server.connection.host
            || connection.port != server.connection.port
            || connection.user.trimmingCharacters(in: .whitespaces) != server.connection.user
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await servers.change(server.id, to: draft, confirming: confirmationReason)
            dismiss()
        } catch ConfirmationKeyError.cancelled {
            // Left as it was, to change or cancel.
        } catch {
            if let refused = ServerFieldProblems(error) {
                problems = refused
                failure = nil
            } else {
                failure = HiveLink.message(for: error)
            }
        }
    }
}
