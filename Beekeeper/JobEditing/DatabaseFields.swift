import HiveKit
import SwiftUI

/// Each database the job dumps, a section apiece.
struct DatabaseFields: View {
    @Binding var databases: [JobEditorDraft.Database]
    let problems: JobFieldProblems

    var body: some View {
        ForEach($databases) { $database in
            Section {
                DatabaseRow(database: $database, problems: problems, index: databases.firstIndex { $0.id == database.id })
            } header: {
                HStack {
                    Text(database.name.isEmpty ? "New Database" : "Database “\(database.name)”")
                    Spacer()
                    Button("Remove", role: .destructive) { databases.removeAll { $0.id == database.id } }
                        .buttonStyle(.borderless)
                        .font(.callout)
                }
            }
        }
        Section {
            Button("Add Database", systemImage: "plus") { databases.append(JobEditorDraft.Database()) }
        } footer: {
            Text("MySQL, MariaDB and Postgres, in a Docker container or on the server itself.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct DatabaseRow: View {
    @Binding var database: JobEditorDraft.Database
    let problems: JobFieldProblems
    let index: Int?

    var body: some View {
        FieldProblemText(problems[.database, index])
        Picker("Kind", selection: $database.kind) {
            Text("MySQL or MariaDB").tag(DatabaseKind.mysql)
            Text("Postgres").tag(DatabaseKind.postgres)
        }
        Picker("Runs", selection: $database.isInContainer) {
            Text("In a Docker container").tag(true)
            Text("On the server").tag(false)
        }
        if database.isInContainer {
            field("Service name", problem: problems[.databaseServiceName, index]) {
                TextField("Service name", text: $database.serviceName, prompt: Text("example_db"))
            } note: {
                Text("Its Swarm or Compose service name. Exactly one running container must match.")
            }
        }
        field("Database", problem: problems[.databaseName, index]) {
            TextField("Database", text: $database.name, prompt: Text("example"))
        }
        field("User", problem: problems[.databaseUser, index]) {
            TextField("User", text: $database.user, prompt: Text("backup"))
        }
        field("Password", problem: problems[.databasePassword, index]) {
            DatabasePasswordField(database: $database)
        } note: {
            if database.kind == .postgres, database.isInContainer {
                Text(
                    "The official Postgres image trusts every connection from inside its container, "
                        + "so a dump can work even with the wrong password."
                )
            }
        }
    }

    private func field(
        _ title: String,
        problem: String?,
        @ViewBuilder input: () -> some View,
        @ViewBuilder note: () -> some View = { EmptyView() }
    ) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                input()
                    .labelsHidden()
                    .autocorrectionDisabled()
                note()
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                FieldProblemText(problem)
            }
        }
    }
}

/// Hive never sends a password back, so a saved one shows only that it's set, with Change to replace it.
private struct DatabasePasswordField: View {
    @Binding var database: JobEditorDraft.Database

    var body: some View {
        if database.hasSavedPassword, database.newPassword == nil {
            HStack {
                Text("Set")
                    .foregroundStyle(.secondary)
                Button("Change…") { database.newPassword = "" }
            }
        } else {
            HStack {
                SecureField("Password", text: newPassword, prompt: Text(database.hasSavedPassword ? "New password" : "Not set"))
                if database.hasSavedPassword {
                    Button("Keep Current") { database.newPassword = nil }
                }
            }
        }
    }

    /// An empty field sends no password, leaving the one Hive has.
    private var newPassword: Binding<String> {
        Binding {
            database.newPassword ?? ""
        } set: { typed in
            database.newPassword = typed.isEmpty && !database.hasSavedPassword ? nil : typed
        }
    }
}
