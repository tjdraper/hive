import HiveKit
import SwiftUI

/// Hive connecting to a server with its key and running a command that changes nothing.
struct ConnectionTestCheck: View {
    let link: HiveLink
    let server: Server
    var testsOnAppear = false

    @State private var result: ConnectionTestResult?
    @State private var isTesting = false
    @State private var failure: String?

    var body: some View {
        Section("Connection Test") {
            HStack(alignment: .firstTextBaseline) {
                outcome
                Spacer()
                Button(result == nil ? "Test Connection" : "Test Again") { Task { await test() } }
                    .disabled(isTesting)
            }
        }
        .task {
            if testsOnAppear { await test() }
        }
    }

    @ViewBuilder private var outcome: some View {
        if isTesting {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting to \(server.connection.host)…")
                    .foregroundStyle(.secondary)
            }
        } else if let failure {
            Label(failure, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if let result, let reason = result.failure {
            Label(reason.message(for: server), systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        } else if let result {
            let seconds = result.seconds.formatted(.number.precision(.fractionLength(1)))
            Label("Hive signed in as \(server.connection.user) in \(seconds) seconds.", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        } else {
            Text("Checks that Hive can sign in with its key.")
                .foregroundStyle(.secondary)
        }
    }

    private func test() async {
        isTesting = true
        failure = nil
        defer { isTesting = false }
        do {
            result = try await link.perform { try await $0.post(HiveEndpoint.connectionTest(onServer: server.id)) }
        } catch {
            result = nil
            failure = HiveLink.message(for: error)
        }
    }
}
