import HiveKit
import SwiftUI

/// Adding a server, from where Hive connects to a passing test connection, or by name only, without SSH
/// details. Also gives a server added without them its SSH details, through the same steps. The server
/// is saved after the first step, so closing the sheet later leaves it listed as not set up, to carry on
/// from its page.
struct AddServerSheet: View {
    let link: HiveLink
    let servers: ServerList
    let onClose: (_ addedServerID: UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step = AddServerStep.connection
    @State private var draft: ServerDraft
    @State private var problems = ServerFieldProblems()
    @State private var serverID: UUID?
    @State private var isSaving = false
    @State private var failure: String?
    /// Set when giving an existing server its SSH details, rather than adding one.
    private let existingName: String?

    /// `existing` is a server without SSH details to give them to.
    init(link: HiveLink, servers: ServerList, addingSSHDetailsTo existing: Server? = nil, onClose: @escaping (UUID) -> Void) {
        self.link = link
        self.servers = servers
        self.onClose = onClose
        existingName = existing?.name
        _serverID = State(initialValue: existing?.id)
        _draft = State(initialValue: existing.map { ServerDraft(name: $0.name, connection: .empty, quotaBytes: nil) } ?? .empty)
    }

    private var server: Server? {
        serverID.flatMap(servers.server)
    }

    private var title: String {
        existingName.map { "Add SSH Details to “\($0)”" } ?? "Add a Server"
    }

    var body: some View {
        SheetLayout(title: title, cancel: cancelButton, confirm: confirmButton, secondary: backButton) {
            VStack(spacing: 0) {
                if draft.connection != nil {
                    AddServerStepIndicator(current: step)
                        .padding()
                    Divider()
                }
                Form {
                    content
                }
                .formStyle(.grouped)
            }
        }
        .macSheetSize(width: 620, height: 560)
    }

    @ViewBuilder private var content: some View {
        switch (step, server) {
        case (.connection, _):
            if existingName != nil {
                Text("Hive needs these before it can back the server up.")
                    .foregroundStyle(.secondary)
            }
            ServerFields(draft: $draft, problems: problems, showsName: existingName == nil, sshDetailsAreOptional: existingName == nil)
            if let failure {
                Text(failure)
                    .foregroundStyle(.red)
            }
        case (.key, let server?):
            AuthorizedKeySetup(link: link, server: server)
        case (.hostKey, let server?):
            HostKeyCheck(link: link, servers: servers, server: server, scansOnAppear: true)
        case (.test, let server?):
            ConnectionTestCheck(link: link, server: server, testsOnAppear: true)
        case (_, nil):
            Text("The server is no longer on this Hive.")
                .foregroundStyle(.secondary)
        }
    }

    /// Once the server is saved with its SSH details, closing leaves it listed as not set up.
    private var cancelButton: SheetButton {
        if let serverID, server?.connection != nil {
            SheetButton(title: "Finish Later") { close(serverID) }
        } else {
            SheetButton(title: "Cancel") { dismiss() }
        }
    }

    private var confirmButton: SheetButton {
        switch step {
        case .connection:
            SheetButton(title: draft.connection == nil ? "Add Server" : "Continue", isDisabled: !draft.isComplete || isSaving) {
                Task { await save() }
            }
        case .key, .hostKey:
            SheetButton(title: "Continue", isDisabled: step == .hostKey && server?.confirmedHostKey == nil) {
                step = step.next ?? step
            }
        case .test:
            SheetButton(title: "Done") { if let serverID { close(serverID) } }
        }
    }

    private var backButton: SheetButton? {
        guard let previous = step.previous, step != .key else { return nil }
        return SheetButton(title: "Back") { step = previous }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let saved: Server
            if let serverID {
                // As the server is now, in case it changed since the sheet opened.
                guard var change = server?.draft else { return }
                change.connection = draft.connection
                saved = try await servers.change(serverID, to: change, confirming: nil)
            } else {
                saved = try await servers.add(draft)
            }
            guard saved.connection != nil else { return close(saved.id) }
            serverID = saved.id
            problems = ServerFieldProblems()
            failure = nil
            step = .key
        } catch {
            if let refused = ServerFieldProblems(error) {
                problems = refused
                failure = nil
            } else {
                failure = HiveLink.message(for: error)
            }
        }
    }

    private func close(_ serverID: UUID) {
        onClose(serverID)
        dismiss()
    }
}

enum AddServerStep: Int, CaseIterable, Comparable {
    case connection
    case key
    case hostKey
    case test

    var title: String {
        switch self {
        case .connection: "Connection"
        case .key: "Hive's Key"
        case .hostKey: "Host Key"
        case .test: "Test"
        }
    }

    var previous: Self? {
        Self(rawValue: rawValue - 1)
    }

    var next: Self? {
        Self(rawValue: rawValue + 1)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

private struct AddServerStepIndicator: View {
    let current: AddServerStep

    var body: some View {
        HStack(spacing: 18) {
            ForEach(AddServerStep.allCases, id: \.self) { step in
                HStack(spacing: 6) {
                    Image(systemName: symbol(for: step))
                        .foregroundStyle(step <= current ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    Text(step.title)
                        .fontWeight(step == current ? .semibold : .regular)
                        .foregroundStyle(step == current ? .primary : .secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current.rawValue + 1) of \(AddServerStep.allCases.count), \(current.title)")
    }

    private func symbol(for step: AddServerStep) -> String {
        step < current ? "checkmark.circle.fill" : "\(step.rawValue + 1).circle\(step == current ? ".fill" : "")"
    }
}
