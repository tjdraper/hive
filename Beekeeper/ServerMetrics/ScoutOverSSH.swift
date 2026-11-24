import Foundation
import HiveKit
import Observation

/// Hive acting on a server's Scout over SSH, through `hive-scout manage`: what Hive can do there, and
/// the action under way and how it went.
@Observable
final class ScoutOverSSH {
    struct Outcome: Equatable {
        let action: ScoutAction
        let succeeded: Bool
        let message: String
    }

    let link: HiveLink
    let server: Server
    private(set) var check: ScoutCheckResult?
    private(set) var checkFailure: String?
    private(set) var isChecking = false
    private(set) var working: ScoutAction?
    private(set) var outcome: Outcome?

    init(link: HiveLink, server: Server) {
        self.link = link
        self.server = server
    }

    /// What Hive found on the server, when it reached it.
    var found: ScoutServerCheck? {
        check?.check
    }

    /// An installed Scout Hive can update, enroll again, give addresses to and uninstall.
    var canManage: Bool {
        guard let found else { return false }
        return found.obstacle == nil && found.access.canManage && found.installedVersion != nil
    }

    /// Hive checks only a server it can sign in to.
    var canCheck: Bool {
        server.connection != nil && server.isSetUp
    }

    func refresh() async {
        guard canCheck, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            check = try await link.perform { try await $0.post(HiveEndpoint.scoutCheck(onServer: server.id)) }
            checkFailure = nil
        } catch is CancellationError {
            return
        } catch {
            check = nil
            checkFailure = HiveLink.message(for: error)
        }
    }

    /// Install and enroll again ask for Touch ID or the password first, since they let a Scout send
    /// figures for the server. Returns whether it was done.
    @discardableResult
    func perform(_ action: ScoutAction) async -> Bool {
        working = action
        outcome = nil
        defer { working = nil }
        let path = HiveEndpoint.scoutAction(onServer: server.id)
        let request = ScoutActionRequest(action: action)
        do {
            let result: ScoutActionResult = switch action {
            case .install, .enrollAgain:
                try await link.confirmed("POST", path, body: request, reason: "let a Scout send figures for “\(server.name)”")
            case .update, .sendAddresses, .uninstall:
                try await link.perform { try await $0.post(path, body: request) }
            }
            outcome = Outcome(action: action, succeeded: result.outcome == .done, message: result.message(for: action, on: server))
        } catch ConfirmationKeyError.cancelled {
            return false
        } catch {
            outcome = Outcome(action: action, succeeded: false, message: HiveLink.message(for: error))
        }
        await refresh()
        return outcome?.succeeded == true
    }

    func clearOutcome() {
        outcome = nil
    }
}

extension ScoutActionResult {
    /// What happened, for people. Scout's own words where it said something, which are the server's.
    func message(for action: ScoutAction, on server: Server) -> String {
        if let failure { return failure.message(for: server) }
        if let problem { return problem.message(for: action) }
        switch outcome {
        case .done:
            return message ?? "Done."
        case .refused:
            return "Scout refused, changing nothing: \(message ?? "it didn't say why.")"
        case .failed:
            return "It stopped part way, so something may have changed: \(message ?? "Scout didn't say why.")"
        }
    }
}

extension ScoutActionProblem {
    func message(for action: ScoutAction) -> String {
        switch self {
        case .noRootAccess:
            "Hive can't run commands as root on this server, so it can't do that itself."
        case .unsupported:
            "Scout doesn't run on this server's system, CPU or init system."
        case .notInstalled:
            "Scout isn't installed on this server, or Hive couldn't ask it its version."
        case .alreadyInstalled:
            "Scout is already installed on this server. Enroll it again instead."
        case .upToDate:
            "This server's Scout is as new as the one the Hive carries."
        case .noCarriedRelease:
            "The Hive doesn't carry a Scout for this server's CPU."
        case .noAddressOptions:
            action == .sendAddresses
                ? "The Hive has no addresses to give. Add one under Addresses for Other Devices in Settings."
                : "Add an address the server can reach the Hive at, under Addresses for Other Devices in Settings."
        }
    }
}

extension ScoutObstacle {
    var message: String {
        switch self {
        case .notLinux: "Scout runs on Linux only, and this server runs another system."
        case .unsupportedCPU: "Scout is built for x86_64 and aarch64 only, and this server has another CPU."
        case .unsupportedInitSystem:
            "This server isn't run by systemd or OpenRC, so Scout can't install itself as a service. "
                + "Its init system can run hive-scout run as the hive-scout user itself."
        }
    }
}
