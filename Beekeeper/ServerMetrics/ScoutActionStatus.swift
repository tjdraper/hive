import HiveKit
import SwiftUI

/// What Hive is doing to a server's Scout over SSH, or how its last action went.
struct ScoutActionStatus: View {
    let ssh: ScoutOverSSH
    let server: Server

    var body: some View {
        if let action = ssh.working {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(action.progress(on: server))
                    .foregroundStyle(.secondary)
            }
        } else if let outcome = ssh.outcome {
            HStack(alignment: .firstTextBaseline) {
                Label(outcome.message, systemImage: outcome.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(outcome.succeeded ? .green : .orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Dismiss") { ssh.clearOutcome() }
                    .buttonStyle(.borderless)
            }
        }
    }
}

extension ScoutAction {
    func progress(on server: Server) -> String {
        switch self {
        case .install: "Installing Scout on “\(server.name)”…"
        case .update: "Updating Scout on “\(server.name)”…"
        case .enrollAgain: "Enrolling Scout on “\(server.name)” again…"
        case .sendAddresses: "Giving Scout the Hive's addresses…"
        case .uninstall: "Uninstalling Scout from “\(server.name)”…"
        }
    }
}
