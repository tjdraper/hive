import HiveKit
import SwiftUI

/// How Hive sends email, in the Hive's settings, and sending a test email to check it.
struct EmailSection: View {
    let hive: KnownHive
    let link: HiveLink

    @State private var state: EmailSettingsState?
    @State private var failure: String?
    @Environment(\.presentFormSheet) private var presentSheet
    @State private var isSendingTest = false
    @State private var testOutcome: TestEmailOutcome?
    @State private var testFailure: String?

    var body: some View {
        Section {
            if let state {
                summary(state)
            } else if let failure {
                Text(failure)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        } header: {
            Text("Email")
        } footer: {
            Text("Hive emails when a backup fails or something needs your attention, through your own email provider.")
                .foregroundStyle(.secondary)
        }
        .task { await load() }
    }

    @ViewBuilder private func summary(_ state: EmailSettingsState) -> some View {
        LabeledContent("Mail server") {
            HStack(spacing: 12) {
                Text(state.settings.map { "\($0.host):\($0.port)" } ?? "Not set up")
                    .foregroundStyle(.secondary)
                Button(state.settings == nil ? "Set Up…" : "Change…") { edit(state) }
            }
        }
        if let settings = state.settings {
            LabeledContent("Sends to", value: settings.recipients.formatted(.list(type: .and)))
            if !settings.username.isEmpty, !state.hasPassword {
                Label("No password is set, so Hive can't send email.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            HStack {
                if isSendingTest {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Send Test Email", systemImage: "paperplane") { Task { await sendTest() } }
                    .disabled(isSendingTest)
            }
            if let testOutcome {
                TestEmailOutcomeView(outcome: testOutcome, recipients: settings.recipients)
            }
            if let testFailure {
                Text(testFailure)
                    .foregroundStyle(.red)
            }
        }
    }

    private func edit(_ state: EmailSettingsState) {
        presentSheet? {
            EmailSettingsSheet(hive: hive, link: link, saved: state) { saved in
                self.state = saved
                testOutcome = nil
                testFailure = nil
            }
        }
    }

    private func load() async {
        do {
            state = try await link.perform { try await $0.get(HiveEndpoint.email) }
            failure = nil
        } catch {
            failure = HiveLink.message(for: error)
        }
    }

    private func sendTest() async {
        isSendingTest = true
        defer { isSendingTest = false }
        testOutcome = nil
        testFailure = nil
        do {
            testOutcome = try await link.perform { try await $0.post(HiveEndpoint.testEmail) }
        } catch {
            testFailure = HiveLink.message(for: error)
        }
    }
}

private struct TestEmailOutcomeView: View {
    let outcome: TestEmailOutcome
    let recipients: [String]

    var body: some View {
        switch outcome {
        case .sent:
            Label("Sent to \(recipients.formatted(.list(type: .and))). Check that it arrived.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let problem, let serverReply):
            VStack(alignment: .leading, spacing: 4) {
                Label(problem.message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                if let serverReply {
                    Text("The server said: \(serverReply)")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

extension EmailProblem {
    var message: String {
        switch self {
        case .notSetUp: "Email isn't set up."
        case .noPassword: "No password is set. Enter it with Change…."
        case .couldNotConnect: "Couldn't reach the mail server. Check its name and port."
        case .timedOut:
            "The mail server stopped answering. If it uses TLS from the start, usually on port 465, choose TLS rather than STARTTLS."
        case .connectionClosed: "The mail server ended the connection. Check the port, and whether it uses STARTTLS or TLS."
        case .secureConnectionFailed:
            "Couldn't make a secure connection. The server may use STARTTLS rather than TLS, or its certificate isn't one "
                + "the Mac trusts for this name."
        case .startTLSUnavailable: "The server doesn't offer STARTTLS, so Hive sent nothing. Try TLS, usually on port 465."
        case .signInUnavailable: "The server offers no way of signing in that Hive supports."
        case .signInRefused: "The server turned down the username or password."
        case .senderRefused: "The server won't send from the From address."
        case .recipientRefused: "The server turned down one of the addresses to send to."
        case .messageRefused: "The server turned down the message."
        case .unexpectedReply: "The server answered something Hive didn't expect."
        }
    }
}
