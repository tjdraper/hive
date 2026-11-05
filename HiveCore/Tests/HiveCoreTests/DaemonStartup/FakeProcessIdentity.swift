import Darwin
@testable import HiveCore

/// Follows the POSIX rules closely enough to test giving up root: only root may change its user or
/// groups, and a process that isn't root can't become root again unless `rootRegainable` is set.
final class FakeProcessIdentity: ProcessIdentity {
    var parentProcessID: pid_t = 1
    var userID: uid_t
    var effectiveUserID: uid_t
    var groupID: gid_t = 0
    var effectiveGroupID: gid_t = 0
    var lastError: Int32 = 0

    var failingCall: String?
    var rootRegainable = false
    var ignoresUserChange = false

    private(set) var calls: [String] = []
    private(set) var environment: [String: String] = [:]

    init(userID: uid_t = 0) {
        self.userID = userID
        self.effectiveUserID = userID
    }

    var isRoot: Bool { effectiveUserID == 0 }

    func initializeGroups(name _: String, groupID _: gid_t) -> Int32 {
        calls.append("initgroups")
        return permit("initgroups", allowed: isRoot) ? 0 : -1
    }

    func setGroupID(_ groupID: gid_t) -> Int32 {
        calls.append("setgid")
        guard permit("setgid", allowed: isRoot) else { return -1 }
        self.groupID = groupID
        effectiveGroupID = groupID
        return 0
    }

    func setUserID(_ userID: uid_t) -> Int32 {
        calls.append("setuid(\(userID))")
        guard permit("setuid", allowed: isRoot || userID == self.userID || rootRegainable) else { return -1 }
        guard !ignoresUserChange else { return 0 }
        self.userID = userID
        effectiveUserID = userID
        return 0
    }

    func setEffectiveUserID(_ userID: uid_t) -> Int32 {
        calls.append("seteuid(\(userID))")
        guard permit("seteuid", allowed: isRoot || userID == self.userID || rootRegainable) else { return -1 }
        effectiveUserID = userID
        return 0
    }

    func setEnvironment(_ name: String, _ value: String) {
        environment[name] = value
    }

    private func permit(_ call: String, allowed: Bool) -> Bool {
        guard allowed, failingCall != call else {
            lastError = EPERM
            return false
        }
        return true
    }
}

struct FakeConsoleUser: ConsoleUserFinding {
    let userID: uid_t?

    func consoleUserID() -> uid_t? {
        userID
    }
}

struct FakeAccounts: UserAccountFinding {
    let accounts: [UserAccount]

    func account(for userID: uid_t) -> UserAccount? {
        accounts.first { $0.userID == userID }
    }
}
