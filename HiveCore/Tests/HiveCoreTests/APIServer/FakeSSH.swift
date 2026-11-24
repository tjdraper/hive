import Foundation
@testable import HiveCore
import HiveKit
import Synchronization

/// Stands in for `ssh` and `ssh-keyscan`, answering what it's told and recording what it was asked.
final class FakeSSH: SSHRunning, HostKeyScanning {
    struct State {
        var scan = HostKeyScanOutcome.failed(.unreachable)
        var result = ChildProcess.Result(status: 0, standardOutput: Data(), standardError: Data())
        var scanned: [ServerConnection] = []
        var ran: [(command: String, target: SSHTarget)] = []
        var inputs: [Data?] = []
        /// Answers in place of `result`, by the command and its input.
        var answer: (@Sendable (String, Data?) -> ChildProcess.Result)?
    }

    private let state = Mutex(State())

    var scanned: [ServerConnection] {
        state.withLock { $0.scanned }
    }

    var ran: [(command: String, target: SSHTarget)] {
        state.withLock { $0.ran }
    }

    /// What each command was given on standard input.
    var inputs: [Data?] {
        state.withLock { $0.inputs }
    }

    func answer(with answer: @escaping @Sendable (String, Data?) -> ChildProcess.Result) {
        state.withLock { $0.answer = answer }
    }

    func setScan(_ outcome: HostKeyScanOutcome) {
        state.withLock { $0.scan = outcome }
    }

    func setResult(status: Int32, standardError: String = "") {
        state.withLock { $0.result = ChildProcess.Result(status: status, standardOutput: Data(), standardError: Data(standardError.utf8)) }
    }

    func scan(_ connection: ServerConnection) async throws -> HostKeyScanOutcome {
        state.withLock { state in
            state.scanned.append(connection)
            return state.scan
        }
    }

    func run(_ remoteCommand: String, input: Data?, on target: SSHTarget) async throws -> ChildProcess.Result {
        state.withLock { state in
            state.ran.append((remoteCommand, target))
            state.inputs.append(input)
            return state.answer?(remoteCommand, input) ?? state.result
        }
    }
}
