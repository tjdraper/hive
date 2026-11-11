import HiveKit
import SwiftUI

/// In the Hive's settings: giving every server a new SSH key of Hive's in one action (§14), such as after
/// a restore when the old Mac may have been stolen, with each server's result as it finishes.
struct SSHKeyRotationSection: View {
    let hive: KnownHive
    let link: HiveLink

    /// Rotation takes a few seconds a server, and waits for a backup that's running to finish.
    private static let pollInterval = Duration.seconds(1)

    @State private var state: SSHKeyRotationState?
    @State private var isAsking = false
    @State private var isStarting = false
    @State private var failure: String?

    var body: some View {
        Section {
            if let state, state.startedAt != nil {
                results(state)
            }
            HStack {
                if let failure {
                    Text(failure)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Rotate SSH Keys…") { isAsking = true }
                    .disabled(isStarting || state?.isRunning == true)
            }
        } header: {
            Text("SSH Keys")
        } footer: {
            Text(
                "Hive signs in to each server with an SSH key of its own. Rotating gives each server a new one and removes "
                    + "the old one from its authorized_keys, so a copy of an old key, such as on a lost Mac, is no use."
            )
            .foregroundStyle(.secondary)
        }
        .confirmationDialog("Give every server of “\(hive.name)” a new SSH key?", isPresented: $isAsking) {
            Button("Rotate SSH Keys") { Task { await start() } }
        } message: {
            Text(
                "Hive adds a new key to each server with its old one, checks it works, then removes the old one. A server "
                    + "where that fails keeps its old key. Rotating waits for a backup that's running to finish."
            )
        }
        .task(id: state?.isRunning == true) { await follow() }
    }

    @ViewBuilder private func results(_ state: SSHKeyRotationState) -> some View {
        if state.isRunning {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(state.results.isEmpty ? "Rotating, once no backup is running…" : "Rotating…")
                    .foregroundStyle(.secondary)
            }
        } else if let finished = state.finishedAt {
            Text("Last rotated \(finished.formatted(date: .abbreviated, time: .shortened))")
                .foregroundStyle(.secondary)
        }
        ForEach(state.results) { result in
            LabeledContent(result.serverName) {
                Label(result.outcome.summary, systemImage: result.outcome.systemImage)
                    .foregroundStyle(result.outcome.isProblem ? .orange : .secondary)
            }
        }
    }

    /// Loads the latest rotation, and while one runs, keeps checking until it's done.
    private func follow() async {
        repeat {
            if let loaded: SSHKeyRotationState = try? await link.perform({ try await $0.get(HiveEndpoint.sshKeyRotation) }) {
                state = loaded
            }
            guard state?.isRunning == true else { return }
            try? await Task.sleep(for: Self.pollInterval)
        } while !Task.isCancelled
    }

    private func start() async {
        isStarting = true
        defer { isStarting = false }
        do {
            let started: SSHKeyRotationState = try await link.confirmed(
                "POST",
                HiveEndpoint.sshKeyRotation,
                reason: "give every server of “\(hive.name)” a new SSH key, removing the old ones"
            )
            state = started
            failure = nil
        } catch ConfirmationKeyError.cancelled {
            return
        } catch let refused as HiveRequestError where refused.status == 409 {
            failure = "Hive is rotating the keys already."
        } catch {
            failure = HiveLink.message(for: error)
        }
    }
}

extension SSHKeyRotationOutcome {
    var summary: String {
        switch self {
        case .rotated: "Rotated"
        case .oldKeyLeft: "New key in use, but the old one is still in authorized_keys"
        case .notSetUp: "Not set up yet"
        case .failed(let failure): failure.summary
        }
    }

    var systemImage: String {
        switch self {
        case .rotated: "checkmark.circle"
        case .notSetUp: "minus.circle"
        case .oldKeyLeft, .failed: "exclamationmark.triangle"
        }
    }

    var isProblem: Bool {
        switch self {
        case .rotated, .notSetUp: false
        case .oldKeyLeft, .failed: true
        }
    }
}

private extension SSHKeyRotationFailure {
    var summary: String {
        switch self {
        case .connection(let failure): "Kept the old key: \(failure.rotationSummary)"
        case .oldKeyNotFound: "Kept the old key: it isn't in ~/.ssh/authorized_keys"
        case .couldNotAddNewKey: "Kept the old key: couldn't add the new one"
        case .newKeyRefused: "Kept the old key: the server turned the new one down"
        case .serverChanged: "Kept the old key: the server changed meanwhile"
        }
    }
}

private extension ConnectionFailure {
    var rotationSummary: String {
        switch self {
        case .noSSHKey, .noConfirmedHostKey: "not set up yet"
        case .hostKeyChanged: "its host key changed"
        case .loginRefused: "the server turned the old key down"
        case .unreachable: "couldn't reach the server"
        case .stalled: "the connection stopped answering"
        case .failed: "something went wrong"
        }
    }
}
