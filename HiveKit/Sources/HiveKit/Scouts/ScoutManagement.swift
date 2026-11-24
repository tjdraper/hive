import Foundation

/// What Hive found it can do about Scout on a server, over SSH, with commands that change nothing.
public struct ScoutServerCheck: Codable, Hashable, Sendable {
    /// The user Hive signs in as.
    public let sshUser: String
    /// Nil for a CPU Scout isn't built for.
    public let platform: ScoutRelease.Platform?
    public let access: ScoutRootAccess
    /// Whether `sudo` or `doas` is installed, which Scout's rule for Hive's user needs.
    public let hasSudoOrDoas: Bool
    /// The version installed, as Scout reported it. Nil when it isn't installed, or Hive couldn't ask it.
    public let installedVersion: String?
    /// Whether `/usr/local/bin/hive-scout` is there, whether or not Hive could ask it its version.
    public let isInstalled: Bool
    /// What keeps Scout off the server, whatever Hive's access.
    public let obstacle: ScoutObstacle?

    public init(
        sshUser: String,
        platform: ScoutRelease.Platform?,
        access: ScoutRootAccess,
        hasSudoOrDoas: Bool,
        installedVersion: String?,
        isInstalled: Bool,
        obstacle: ScoutObstacle?
    ) {
        self.sshUser = sshUser
        self.platform = platform
        self.access = access
        self.hasSudoOrDoas = hasSudoOrDoas
        self.installedVersion = installedVersion
        self.isInstalled = isInstalled
        self.obstacle = obstacle
    }
}

/// How Hive's SSH user can act as root, for Scout. `-n` never asks for a password, and Hive never
/// holds or sends one, so `sudo` asking for one counts as none.
public enum ScoutRootAccess: String, Codable, Hashable, Sendable {
    /// Hive signs in as root.
    case root
    /// Passwordless `sudo` for any command.
    case sudo
    /// Passwordless `doas` for any command.
    case doas
    /// Only Scout's own management command, through the `sudo` rule its install wrote.
    case sudoRule
    /// Only Scout's own management command, through the `doas` rule its install wrote.
    case doasRule
    case none

    /// Hive can put a Scout on the server itself.
    public var canInstall: Bool {
        [.root, .sudo, .doas].contains(self)
    }

    /// Hive can update, enroll again, send new addresses to and uninstall an installed Scout.
    public var canManage: Bool {
        self != .none
    }
}

public enum ScoutObstacle: String, Codable, Hashable, Sendable {
    /// Scout runs on Linux only, for now.
    case notLinux
    case unsupportedCPU
    /// Neither systemd nor OpenRC started the server.
    case unsupportedInitSystem
}

/// What `POST HiveEndpoint.scoutCheck(onServer:)` answers.
public struct ScoutCheckResult: Codable, Hashable, Sendable {
    /// Nil when Hive couldn't reach the server, or didn't try.
    public let check: ScoutServerCheck?
    public let failure: ConnectionFailure?

    public init(check: ScoutServerCheck?, failure: ConnectionFailure?) {
        self.check = check
        self.failure = failure
    }
}

/// What Hive does to a server's Scout through `hive-scout manage`, over SSH.
public enum ScoutAction: String, Codable, Hashable, Sendable, CaseIterable {
    /// Installs the Scout Hive.app carries and enrolls it, where Hive has root. Confirmed.
    case install
    /// Replaces the installed Scout with the newer release Hive.app carries, which the installed
    /// Scout checks is signed for it before it takes it.
    case update
    /// Enrolls the installed Scout again, such as after a restore or a new identity. Confirmed.
    case enrollAgain
    /// Gives the installed Scout the Hive's address options, keeping its enrollment.
    case sendAddresses
    /// Removes Scout from the server, and the server's metrics with it.
    case uninstall
}

public struct ScoutActionRequest: Codable, Hashable, Sendable {
    public let action: ScoutAction

    public init(action: ScoutAction) {
        self.action = action
    }
}

/// What `POST HiveEndpoint.scoutAction(onServer:)` answers.
public struct ScoutActionResult: Codable, Hashable, Sendable {
    public enum Outcome: String, Codable, Hashable, Sendable {
        case done
        /// Nothing was changed: Hive refused before running anything, or Scout refused.
        case refused
        /// Something may have changed before it stopped.
        case failed
    }

    public let outcome: Outcome
    /// Why Hive refused before running anything.
    public let problem: ScoutActionProblem?
    /// Why Hive couldn't reach the server.
    public let failure: ConnectionFailure?
    /// What Scout said, for people. The server's words, and never the enrollment code.
    public let message: String?
    /// The version installed once it's done, as Scout reported it.
    public let version: String?

    public init(outcome: Outcome, problem: ScoutActionProblem?, failure: ConnectionFailure?, message: String?, version: String?) {
        self.outcome = outcome
        self.problem = problem
        self.failure = failure
        self.message = message
        self.version = version
    }
}

/// Why Hive refused a `ScoutAction` before running anything on the server.
public enum ScoutActionProblem: String, Codable, Hashable, Sendable {
    /// Hive can't act as root on the server, beyond Scout's rule for some actions.
    case noRootAccess
    case unsupported
    case notInstalled
    /// Install puts a Scout only where there's none; enroll again or update one that's there.
    case alreadyInstalled
    /// The installed Scout is as new as the one Hive.app carries, or newer.
    case upToDate
    /// Hive.app doesn't carry a Scout for the server's CPU, or carries one whose statement doesn't match it.
    case noCarriedRelease
    /// A code without an address would give the Scout nowhere to reach the Hive.
    case noAddressOptions
}
