import Foundation
import GRDB
import HiveKit
import os
import ScoutProtocol

/// Hive acting on a server's Scout over SSH with the server's confirmed host key: finding out what it
/// can do, then installing, updating, enrolling again, sending new addresses or uninstalling, all
/// through `hive-scout manage`. Installing and enrolling again open an enrollment window in the same
/// confirmed action, since they give something new access.
struct ScoutManagementWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Scouts")
    /// Far longer than anything Scout says, so a server can't hand Beekeeper a page of text.
    static let longestMessage = 2000

    let targets: SSHTargetLoader
    let ssh: any SSHRunning
    let carried: CarriedScout?
    let settings: HiveSettingsStore
    let database: HiveDatabase
    let windows: EnrollmentWindowWorkflow
    let metricsRemoval: MetricsRemovalWorkflow
    let now: @Sendable () -> Date

    /// Nil when there's no such server.
    func check(serverID: UUID) async throws -> ScoutCheckResult? {
        guard let lookup = try targets.target(forServer: serverID) else { return nil }
        switch lookup {
        case .unavailable(let reason):
            return ScoutCheckResult(check: nil, failure: reason)
        case .ready(let target):
            switch try await probe(target) {
            case .found(let check): return ScoutCheckResult(check: check, failure: nil)
            case .unreachable(let failure): return ScoutCheckResult(check: nil, failure: failure)
            }
        }
    }

    /// Throws `ConfirmationError.required`, running nothing, for an action that needs confirming and
    /// wasn't. Nil when there's no such server.
    func perform(
        _ action: ScoutAction,
        onServer serverID: UUID,
        isConfirmed: Bool,
        by deviceID: UUID
    ) async throws -> ScoutActionResult? {
        if [.install, .enrollAgain].contains(action) {
            try ConfirmationRequirement.check([.enrollmentWindowOpened], isConfirmed: isConfirmed)
        }
        let target: SSHTarget
        switch try targets.target(forServer: serverID) {
        case nil: return nil
        case .unavailable(let reason): return .refused(failure: reason)
        case .ready(let ready): target = ready
        }
        let plan: ScoutActionPlan
        switch try await planned(action, on: target) {
        case .plan(let made): plan = made
        case .refused(let refusal): return refusal
        }

        var code: String?
        if plan.needsCode {
            do {
                guard let window = try windows.open(forServer: serverID, isConfirmed: isConfirmed, by: deviceID) else { return nil }
                code = window.code
            } catch EnrollmentWindowError.refused(.noAddressOptions) {
                return .refused(problem: .noAddressOptions)
            }
        }
        let result = try await run(plan, code: code, action: action, on: target)
        if code != nil, result.outcome != .done { try windows.close(forServer: serverID, by: deviceID) }
        try record(action, result: result, serverID: serverID, by: deviceID)
        return result
    }

    private enum Planned {
        case plan(ScoutActionPlan)
        case refused(ScoutActionResult)
    }

    private func planned(_ action: ScoutAction, on target: SSHTarget) async throws -> Planned {
        let check: ScoutServerCheck
        switch try await probe(target) {
        case .found(let found): check = found
        case .unreachable(let failure): return .refused(.refused(failure: failure))
        }
        let addresses = try settings.settings().addresses.options.map { EnrollmentCode.Address(host: $0.host, port: $0.port) }
        switch ScoutActionPlan.make(action, check: check, carried: carried, addresses: addresses) {
        case .plan(let plan):
            return .plan(plan)
        case .refused(let problem):
            Self.logger.notice("Refused a Scout action (\(action.rawValue, privacy: .public)): \(problem.rawValue, privacy: .public)")
            return .refused(.refused(problem: problem))
        }
    }

    private enum ProbeOutcome {
        case found(ScoutServerCheck)
        case unreachable(ConnectionFailure)
    }

    private func probe(_ target: SSHTarget) async throws -> ProbeOutcome {
        let answer = try await ssh.run(ScoutProbe.command, on: target)
        if let failure = SSHFailureReader.failure(in: answer) {
            Self.logger.error("Couldn't check Scout on a server: \(failure.rawValue, privacy: .public)")
            return .unreachable(failure)
        }
        guard let check = ScoutProbe.check(in: answer.standardOutput, sshUser: target.connection.user) else {
            Self.logger.error("Couldn't read what a server said about Scout")
            return .unreachable(.failed)
        }
        return .found(check)
    }

    private func run(
        _ plan: ScoutActionPlan,
        code: String?,
        action: ScoutAction,
        on target: SSHTarget
    ) async throws -> ScoutActionResult {
        let started = ContinuousClock.now
        let answer = try await ssh.run(plan.command, input: plan.input(code: code), on: target)
        let seconds = (ContinuousClock.now - started).roundedSeconds
        let result = Self.result(of: answer)
        let (name, outcome) = (action.rawValue, result.outcome.rawValue)
        Self.logger.notice("Scout action \(name, privacy: .public): \(outcome, privacy: .public) in \(seconds, privacy: .public)s")
        return result
    }

    /// From Scout's answer, the last line it wrote. Without one, `ssh` or the shell stopped first, and
    /// what it wrote to standard error is all there is to say.
    static func result(of answer: ChildProcess.Result) -> ScoutActionResult {
        let lastLine = String(bytes: answer.standardOutput, encoding: .utf8)?
            .split(separator: "\n").last.map { Data($0.utf8) } ?? Data()
        guard let response = try? JSONDecoder().decode(ManagementResponse.self, from: lastLine) else {
            let said = String(bytes: answer.standardError, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let failure = SSHFailureReader.failure(in: answer)
            return ScoutActionResult(outcome: .failed, problem: nil, failure: failure, message: said.map(shortened), version: nil)
        }
        let outcome: ScoutActionResult.Outcome = switch response.outcome {
        case .done: .done
        case .refused: .refused
        case .failed: .failed
        }
        let version = ScoutVersion(parsing: response.version)?.description
        return ScoutActionResult(outcome: outcome, problem: nil, failure: nil, message: shortened(response.message), version: version)
    }

    private static func shortened(_ text: String) -> String {
        text.count > longestMessage ? String(text.prefix(longestMessage)) + "…" : text
    }

    /// What changed, or may have, with the device that asked. Enrolling records itself when the Scout
    /// enrolls, and uninstalling removes the server's metrics, which records that too.
    private func record(_ action: ScoutAction, result: ScoutActionResult, serverID: UUID, by deviceID: UUID) throws {
        let change: ScoutChange? = switch (result.outcome, action) {
        case (.refused, _), (.done, .enrollAgain): nil
        case (.failed, _): .actionFailed(action)
        case (.done, .install): .installed(version: result.version ?? "")
        case (.done, .update): .updated(version: result.version ?? "")
        case (.done, .sendAddresses): .addressesSent
        case (.done, .uninstall): .uninstalled
        }
        if let change {
            try database.writer.write { database in
                guard let serverName = try ScoutStore.serverName(serverID, in: database) else { return }
                let event = AuditEvent.scout(serverID: serverID, serverName: serverName, change: change)
                try AuditLog.record(event, by: deviceID, at: now(), in: database)
            }
        }
        if result.outcome == .done, action == .uninstall {
            _ = try metricsRemoval.remove(forServer: serverID, by: deviceID)
        }
    }
}

private extension ScoutActionResult {
    static func refused(problem: ScoutActionProblem? = nil, failure: ConnectionFailure? = nil) -> Self {
        Self(outcome: .refused, problem: problem, failure: failure, message: nil, version: nil)
    }
}
