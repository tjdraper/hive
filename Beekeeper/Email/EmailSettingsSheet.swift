import HiveKit
import SwiftUI

/// Setting up or changing how Hive sends email. Changing the host clears the password, so it has to be
/// entered again, and asks for Touch ID or the password on Save.
struct EmailSettingsSheet: View {
    let hive: KnownHive
    let link: HiveLink
    let saved: EmailSettingsState
    let onSaved: (EmailSettingsState) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: EmailDraft
    @State private var problems = EmailFieldProblems()
    @State private var isSaving = false
    @State private var isAskingToTurnOff = false
    @State private var failure: String?

    init(hive: KnownHive, link: HiveLink, saved: EmailSettingsState, onSaved: @escaping (EmailSettingsState) -> Void) {
        self.hive = hive
        self.link = link
        self.saved = saved
        self.onSaved = onSaved
        _draft = State(initialValue: EmailDraft(saved.settings))
    }

    var body: some View {
        SheetLayout(
            title: "Email",
            cancel: SheetButton(title: "Cancel") { dismiss() },
            confirm: SheetButton(title: "Save", isDisabled: !isChanged || !draft.isComplete || isSaving) { Task { await save() } }
        ) {
            Form {
                serverSection
                signInSection
                addressSection
                if let failure {
                    Text(failure)
                        .foregroundStyle(.red)
                }
                if saved.settings != nil {
                    Section {
                        Button("Turn Off Email…", systemImage: "envelope.badge.minus", role: .destructive) { isAskingToTurnOff = true }
                            .disabled(isSaving)
                    } footer: {
                        Text("Hive stops sending alerts, and forgets these settings and the password.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .macSheetSize(width: 560, height: 640)
        .confirmationDialog("Turn off email for “\(hive.name)”?", isPresented: $isAskingToTurnOff) {
            Button("Turn Off Email", role: .destructive) { Task { await turnOff() } }
        } message: {
            Text("Hive won't be able to tell anyone when a backup fails until email is set up again.")
        }
    }

    private var serverSection: some View {
        Section {
            field("Mail server", problems: problems[.host]) {
                TextField("Mail server", text: $draft.host, prompt: Text("smtp.example.com"))
                    .autocorrectionDisabled()
            }
            Picker("Security", selection: Binding { draft.security } set: { draft.choose($0) }) {
                Text("STARTTLS").tag(EmailSecurity.startTLS)
                Text("TLS").tag(EmailSecurity.implicitTLS)
            }
            field("Port", problems: problems[.port]) {
                TextField("Port", value: $draft.port, format: .number.grouping(.never))
            }
        } header: {
            Text("Mail Server")
        } footer: {
            Text(
                "Your email provider's SMTP server. STARTTLS usually uses port 587, and TLS port 465. Hive only "
                    + "sends over a secure connection, and only to a server whose certificate the Mac trusts."
            )
            .foregroundStyle(.secondary)
        }
    }

    private var signInSection: some View {
        Section {
            field("Username", problems: problems[.user]) {
                TextField("Username", text: $draft.username, prompt: Text("Usually your email address"))
                    .autocorrectionDisabled()
            }
            field("Password", problems: problems[.password]) {
                EmailPasswordField(draft: $draft, hasSavedPassword: keepsSavedPassword)
            }
            if draft.changesHost(from: saved.settings), saved.hasPassword {
                Label(
                    "A new mail server clears the password, so it's never sent anywhere you didn't enter it for. Enter it again.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Signing In")
        } footer: {
            Text("Many providers ask for an app password here rather than your account's own password.")
                .foregroundStyle(.secondary)
        }
    }

    private var addressSection: some View {
        Section {
            field("From", problems: problems[.senderAddress]) {
                TextField("From", text: $draft.senderAddress, prompt: Text("hive@example.com"))
                    .autocorrectionDisabled()
            }
            field("Send alerts to", problems: problems[.recipients]) {
                TextField("Send alerts to", text: $draft.recipients, prompt: Text("One address per line"), axis: .vertical)
                    .lineLimit(2 ... 6)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Addresses")
        } footer: {
            Text("Email comes from “\(hive.name)” at the From address, which your provider has to allow you to send from.")
                .foregroundStyle(.secondary)
        }
    }

    private func field(_ title: String, problems: [String], @ViewBuilder input: () -> some View) -> some View {
        StackedRow(title: title) {
            input()
                .stackedField(title)
            FieldProblemText(problems)
        }
    }

    private var keepsSavedPassword: Bool {
        saved.hasPassword && !draft.changesHost(from: saved.settings)
    }

    private var isChanged: Bool {
        let settingsChanged = saved.settings.map { draft.settings != $0 } ?? true
        return settingsChanged || draft.change.password != nil
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let change = draft.change
        let reason = draft.changesHost(from: saved.settings)
            ? "change the mail server “\(hive.name)” sends email through to \(change.settings.host)"
            : nil
        do {
            let state: EmailSettingsState = try await link.confirmed("PUT", HiveEndpoint.email, body: change, reason: reason)
            onSaved(state)
            dismiss()
        } catch ConfirmationKeyError.cancelled {
            return
        } catch {
            if let refused = EmailFieldProblems(error, recipients: change.settings.recipients) {
                problems = refused
                failure = nil
            } else {
                problems = EmailFieldProblems()
                failure = HiveLink.message(for: error)
            }
        }
    }

    private func turnOff() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await link.perform { try await $0.delete(HiveEndpoint.email) }
            onSaved(EmailSettingsState(settings: nil, hasPassword: false))
            dismiss()
        } catch {
            failure = HiveLink.message(for: error)
        }
    }
}

/// Hive never sends a password back, so a saved one shows only that it's set, with Change to replace it.
private struct EmailPasswordField: View {
    @Binding var draft: EmailDraft
    let hasSavedPassword: Bool

    var body: some View {
        if hasSavedPassword, draft.newPassword == nil {
            HStack {
                Text("Set")
                    .foregroundStyle(.secondary)
                Button("Change…") { draft.newPassword = "" }
            }
        } else {
            HStack {
                SecureField("Password", text: newPassword, prompt: Text(hasSavedPassword ? "New password" : "Not set"))
                if hasSavedPassword {
                    Button("Keep Current") { draft.newPassword = nil }
                }
            }
        }
    }

    /// An empty field sends no password, leaving the one Hive has.
    private var newPassword: Binding<String> {
        Binding {
            draft.newPassword ?? ""
        } set: { typed in
            draft.newPassword = typed.isEmpty && !hasSavedPassword ? nil : typed
        }
    }
}
