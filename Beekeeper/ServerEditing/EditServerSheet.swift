import HiveKit
import SwiftUI

/// Changing a server's name or where Hive connects.
struct EditServerSheet: View {
    let servers: ServerList
    let server: Server

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ServerDraft
    @State private var problems = ServerFieldProblems()
    @State private var isSaving = false
    @State private var failure: String?

    init(servers: ServerList, server: Server) {
        self.servers = servers
        self.server = server
        _draft = State(initialValue: server.draft)
    }

    var body: some View {
        VStack(spacing: 0) {
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
                if let failure {
                    Text(failure)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft == server.draft || !draft.isComplete || isSaving)
            }
            .padding()
        }
        .frame(width: 520, height: 420)
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
            _ = try await servers.change(server.id, to: draft)
            dismiss()
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
