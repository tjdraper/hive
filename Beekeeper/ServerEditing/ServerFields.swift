import HiveKit
import SwiftUI

/// A server's name and, when it has them, its SSH details, with Hive's reason beside any field it turned down.
struct ServerFields: View {
    @Binding var draft: ServerDraft
    let problems: ServerFieldProblems
    var showsName = true
    /// When adding a server, which can go without SSH details. Otherwise the fields follow what the draft has.
    var sshDetailsAreOptional = false

    @State private var setAside: ServerConnection?

    var body: some View {
        Section {
            if showsName {
                ServerFieldRow(title: "Name", problem: problems[.name]) {
                    TextField("Name", text: $draft.name, prompt: Text("Web 1"))
                }
            }
            if sshDetailsAreOptional {
                Toggle("Connect over SSH", isOn: connectsOverSSH)
            }
            if draft.connection != nil {
                ServerFieldRow(title: "Host", problem: problems[.host]) {
                    TextField("Host", text: connection(\.host), prompt: Text("web1.example.com"))
                        .autocorrectionDisabled()
                }
                ServerFieldRow(title: "Port", problem: problems[.port]) {
                    TextField("Port", value: connection(\.port), format: .number.grouping(.never))
                }
                ServerFieldRow(title: "SSH user", problem: problems[.user]) {
                    TextField("SSH user", text: connection(\.user), prompt: Text("root"))
                        .autocorrectionDisabled()
                }
            }
        } footer: {
            Group {
                if draft.connection != nil {
                    Text("The host is a name or address the Hive's Mac can reach, such as a Tailscale name.")
                } else if sshDetailsAreOptional {
                    Text("Hive needs SSH details to back the server up. You can add them later from its page.")
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    /// Not `Binding($draft.connection)`, whose fields crash when they're updated once more after the
    /// connection is turned off.
    private func connection<Value>(_ field: WritableKeyPath<ServerConnection, Value>) -> Binding<Value> {
        Binding {
            (draft.connection ?? .empty)[keyPath: field]
        } set: {
            draft.connection?[keyPath: field] = $0
        }
    }

    /// Turning it off and on again keeps what was typed.
    private var connectsOverSSH: Binding<Bool> {
        Binding {
            draft.connection != nil
        } set: { isOn in
            if isOn {
                draft.connection = setAside ?? .empty
            } else {
                setAside = draft.connection
                draft.connection = nil
            }
        }
    }
}

private struct ServerFieldRow<Input: View>: View {
    let title: String
    let problem: String?
    @ViewBuilder let input: Input

    var body: some View {
        StackedRow(title: title) {
            input
                .stackedField(title)
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

extension ServerDraft {
    static var empty: ServerDraft {
        ServerDraft(name: "", connection: .empty, quotaBytes: nil)
    }

    /// Hive checks the rest, and says which field it turned down.
    var isComplete: Bool {
        let required = [name] + (connection.map { [$0.host, $0.user] } ?? [])
        return required.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

extension ServerConnection {
    static var empty: ServerConnection {
        ServerConnection(host: "", user: "")
    }
}

/// What Hive said was wrong with each field of a server it turned down.
struct ServerFieldProblems {
    private var messages: [ConfigurationField: String] = [:]

    init() {}

    /// Nil when the error isn't Hive turning the server down.
    init?(_ error: any Error) {
        guard let refused = error as? HiveRequestError, refused.status == 422,
              let refusal = try? JSONDecoder().decode(ConfigurationRefusal.self, from: refused.body)
        else { return nil }
        for problem in refusal.problems {
            messages[problem.field] = Self.message(for: problem)
        }
    }

    subscript(field: ConfigurationField) -> String? {
        messages[field]
    }

    private static func message(for problem: ConfigurationProblem) -> String {
        switch (problem.field, problem.reason) {
        case (.name, .duplicate): "Another server already has this name."
        case (.name, _): "Enter a name of up to 100 characters."
        case (.host, _): "Enter a host name or address, such as web1.example.com or 100.64.0.7."
        case (.port, _): "Choose a port from 1 to 65535."
        case (.user, _): "Enter a user name of letters, digits, “-”, “.” and “_”, not starting with “-”."
        case (.quota, _): "Choose a quota above zero."
        default: "Hive turned this down."
        }
    }
}
