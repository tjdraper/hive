import os

public enum RecordedUserResetError: Error, Equatable {
    case needsRoot
}

/// Forgets the recorded user, so the daemon's next start records whoever is logged in at the screen.
/// Root only: choosing the account the daemon becomes is an administrator's decision.
public struct RecordedUserReset {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "DaemonStartup")

    let process: any ProcessIdentity
    let recordedUsers: RecordedUserStore

    public init(process: any ProcessIdentity = CurrentProcessIdentity(), recordedUsers: RecordedUserStore = RecordedUserStore()) {
        self.process = process
        self.recordedUsers = recordedUsers
    }

    public func run() throws {
        guard process.effectiveUserID == 0 else { throw RecordedUserResetError.needsRoot }
        try recordedUsers.clear()
        Self.logger.notice("Cleared the recorded user")
    }
}
