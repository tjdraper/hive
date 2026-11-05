import Darwin
import Foundation
import os

public enum DaemonLaunchMode: Sendable {
    /// Installed with SMAppService. launchd starts it as root, and it becomes the recorded user.
    case systemDaemon
    /// A Debug build that install-test-build.sh --mac runs as a user agent, so it starts as the developer.
    case developmentAgent

    var dataDirectoryName: String {
        switch self {
        case .systemDaemon: "Hive"
        case .developmentAgent: "Hive (Debug)"
        }
    }
}

public enum DaemonStartupError: Error, Equatable {
    case notStartedByLaunchd
    case systemDaemonNotRoot
    case developmentAgentIsRoot
    case bundleNotFound
    case nobodyLoggedIn
    case systemAccount(userID: uid_t)
    case unknownAccount(userID: uid_t)
}

public struct StartedDaemon: Sendable {
    public let account: UserAccount
    public let dataDirectory: URL
    public let fullDiskAccess: FullDiskAccess
}

/// Everything the daemon does before its real work. Until the user switch, it only checks who owns
/// Hive.app and reads or writes the recorded user: nothing touches the network, keys or secrets while it's root.
public struct DaemonStartupWorkflow {
    /// macOS numbers people's accounts from 501. Lower IDs belong to root and system services.
    static let firstPersonUserID: uid_t = 501

    /// At notice level, because macOS keeps info-level entries only briefly, and a start nobody watched
    /// may need explaining hours later.
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "DaemonStartup")

    let mode: DaemonLaunchMode
    let process: any ProcessIdentity
    let installedBundle: InstalledBundleCheck?
    let recordedUsers: RecordedUserStore
    let consoleUsers: any ConsoleUserFinding
    let accounts: any UserAccountFinding
    let dataDirectories: DataDirectoryBuilder
    let fullDiskAccessProbe: FullDiskAccessProbe

    public init(
        mode: DaemonLaunchMode,
        process: any ProcessIdentity = CurrentProcessIdentity(),
        installedBundle: InstalledBundleCheck? = .forCurrentExecutable(),
        recordedUsers: RecordedUserStore = RecordedUserStore(),
        consoleUsers: any ConsoleUserFinding = ConsoleUserFinder(),
        accounts: any UserAccountFinding = UserAccountDirectory(),
        dataDirectories: DataDirectoryBuilder = DataDirectoryBuilder(),
        fullDiskAccessProbe: FullDiskAccessProbe = FullDiskAccessProbe()
    ) {
        self.mode = mode
        self.process = process
        self.installedBundle = installedBundle
        self.recordedUsers = recordedUsers
        self.consoleUsers = consoleUsers
        self.accounts = accounts
        self.dataDirectories = dataDirectories
        self.fullDiskAccessProbe = fullDiskAccessProbe
    }

    public func run() throws -> StartedDaemon {
        // A copy started by hand would share the installed daemon's data, or run as root unchecked.
        guard process.parentProcessID == 1 else { throw DaemonStartupError.notStartedByLaunchd }

        let account = switch mode {
        case .systemDaemon: try becomeRecordedUser()
        case .developmentAgent: try continueAsDeveloper()
        }

        let dataDirectory = try dataDirectories.prepare(named: mode.dataDirectoryName, for: account)
        Self.logger.notice("Data directory ready")

        let fullDiskAccess = fullDiskAccessProbe.check()
        if fullDiskAccess == .granted {
            Self.logger.notice("Full Disk Access: granted")
        } else {
            Self.logger.error("Full Disk Access: \(fullDiskAccess.rawValue, privacy: .public)")
        }

        return StartedDaemon(account: account, dataDirectory: dataDirectory, fullDiskAccess: fullDiskAccess)
    }

    private func becomeRecordedUser() throws -> UserAccount {
        Self.logger.notice("Starting as the system daemon")
        guard process.effectiveUserID == 0 else { throw DaemonStartupError.systemDaemonNotRoot }

        guard let installedBundle else { throw DaemonStartupError.bundleNotFound }
        try installedBundle.verify()
        Self.logger.notice("Hive.app is owned by root and only root can change it")

        let userID = try recordedOrConsoleUserID()
        guard let account = accounts.account(for: userID) else {
            throw DaemonStartupError.unknownAccount(userID: userID)
        }

        try UserSwitch(process: process).become(account)
        Self.logger.notice(
            "Gave up root, running as \(account.name, privacy: .private) (user ID \(account.userID, privacy: .public))"
        )
        return account
    }

    private func recordedOrConsoleUserID() throws -> uid_t {
        if let recorded = try recordedUsers.read() {
            try checkIsPerson(recorded.userID)
            Self.logger.notice("Read the recorded user (user ID \(recorded.userID, privacy: .public))")
            return recorded.userID
        }

        guard let consoleUserID = consoleUsers.consoleUserID() else { throw DaemonStartupError.nobodyLoggedIn }
        try checkIsPerson(consoleUserID)
        try recordedUsers.write(RecordedUser(userID: consoleUserID))
        Self.logger.notice("Recorded the user logged in at the screen (user ID \(consoleUserID, privacy: .public))")
        return consoleUserID
    }

    private func checkIsPerson(_ userID: uid_t) throws {
        guard userID >= Self.firstPersonUserID else { throw DaemonStartupError.systemAccount(userID: userID) }
    }

    private func continueAsDeveloper() throws -> UserAccount {
        Self.logger.notice("Starting as the development agent")
        let userID = process.effectiveUserID
        guard userID != 0 else { throw DaemonStartupError.developmentAgentIsRoot }
        guard let account = accounts.account(for: userID) else {
            throw DaemonStartupError.unknownAccount(userID: userID)
        }
        Self.logger.notice("Running as \(account.name, privacy: .private) (user ID \(userID, privacy: .public))")
        return account
    }
}
