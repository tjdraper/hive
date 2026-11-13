import HiveKit
import SwiftUI

/// Adding a server, from where Hive connects to a passing test connection. The server is saved after
/// the first step, so closing the sheet later leaves it listed as not set up, to carry on from its page.
struct AddServerSheet: View {
    let link: HiveLink
    let servers: ServerList
    let onClose: (_ addedServerID: UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step = AddServerStep.connection
    @State private var draft = ServerDraft.empty
    @State private var problems = ServerFieldProblems()
    @State private var serverID: UUID?
    @State private var isSaving = false
    @State private var failure: String?

    private var server: Server? {
        serverID.flatMap(servers.server)
    }

    var body: some View {
        VStack(spacing: 0) {
            AddServerStepIndicator(current: step)
                .padding()
            Divider()
            Form {
                content
            }
            .formStyle(.grouped)
            Divider()
            footer
                .padding()
        }
        .macSheetSize(width: 620, height: 560)
    }

    @ViewBuilder private var content: some View {
        switch (step, server) {
        case (.connection, _):
            ServerFields(draft: $draft, problems: problems)
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

    private var footer: some View {
        HStack {
            if let serverID {
                Button("Finish Later") { close(serverID) }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            if let previous = step.previous, step != .key {
                Button("Back") { step = previous }
            }
            switch step {
            case .connection:
                Button("Continue") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isComplete || isSaving)
            case .key, .hostKey:
                Button("Continue") { step = step.next ?? step }
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == .hostKey && server?.confirmedHostKey == nil)
            case .test:
                Button("Done") { if let serverID { close(serverID) } }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let added = try await servers.add(draft)
            serverID = added.id
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
