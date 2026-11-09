import HiveKit
import SwiftUI

/// A server's name and where Hive connects, with Hive's reason beside any field it turned down.
struct ServerFields: View {
    @Binding var draft: ServerDraft
    let problems: ServerFieldProblems

    var body: some View {
        Section {
            field("Name", problem: problems[.name]) {
                TextField("Name", text: $draft.name, prompt: Text("Web 1"))
            }
            field("Host", problem: problems[.host]) {
                TextField("Host", text: $draft.connection.host, prompt: Text("web1.example.com"))
                    .autocorrectionDisabled()
            }
            field("Port", problem: problems[.port]) {
                TextField("Port", value: $draft.connection.port, format: .number.grouping(.never))
            }
            field("SSH user", problem: problems[.user]) {
                TextField("SSH user", text: $draft.connection.user, prompt: Text("root"))
                    .autocorrectionDisabled()
            }
        } footer: {
            Text("The host is a name or address the Hive's Mac can reach, such as a Tailscale name.")
                .foregroundStyle(.secondary)
        }
    }

    private func field(_ title: String, problem: String?, @ViewBuilder input: () -> some View) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                input()
                    .labelsHidden()
                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

extension ServerDraft {
    static var empty: ServerDraft {
        ServerDraft(name: "", connection: ServerConnection(host: "", user: ""), quotaBytes: nil)
    }

    /// Hive checks the rest, and says which field it turned down.
    var isComplete: Bool {
        [name, connection.host, connection.user].allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
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
