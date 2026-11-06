import Foundation
import HiveKit
import os

/// Connecting to a server with Hive's key and running a command that changes nothing, to check the
/// key is in `authorized_keys` and the host key is still the confirmed one.
struct ConnectionTestWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "SSH")
    static let harmlessCommand = "true"

    let targets: SSHTargetLoader
    let ssh: any SSHRunning

    /// Nil when no server has that ID.
    func test(serverID: UUID) async throws -> ConnectionTestResult? {
        guard let lookup = try targets.target(forServer: serverID) else { return nil }
        let target: SSHTarget
        switch lookup {
        case .ready(let ready):
            target = ready
        case .unavailable(let reason):
            Self.logger.notice("Didn't test a connection: \(reason.rawValue, privacy: .public)")
            return ConnectionTestResult(failure: reason, seconds: 0)
        }

        let started = ContinuousClock.now
        let result = try await ssh.run(Self.harmlessCommand, on: target)
        let seconds = (ContinuousClock.now - started).roundedSeconds
        let failure = SSHFailureReader.failure(in: result)
        if let failure {
            let (reason, status) = (failure.rawValue, result.status)
            Self.logger.error(
                "Connection test failed: \(reason, privacy: .public), exit \(status, privacy: .public), after \(seconds, privacy: .public)s"
            )
        } else {
            Self.logger.notice("Connection test passed in \(seconds, privacy: .public)s")
        }
        return ConnectionTestResult(failure: failure, seconds: seconds)
    }
}
