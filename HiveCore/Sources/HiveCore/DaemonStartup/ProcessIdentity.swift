import Darwin

/// The calls that decide which account this process runs as, so starting up can be tested without root.
public protocol ProcessIdentity {
    var parentProcessID: pid_t { get }
    var userID: uid_t { get }
    var effectiveUserID: uid_t { get }
    var groupID: gid_t { get }
    var effectiveGroupID: gid_t { get }
    var lastError: Int32 { get }

    func initializeGroups(name: String, groupID: gid_t) -> Int32
    func setGroupID(_ groupID: gid_t) -> Int32
    func setUserID(_ userID: uid_t) -> Int32
    func setEffectiveUserID(_ userID: uid_t) -> Int32
    func setEnvironment(_ name: String, _ value: String)
}

public struct CurrentProcessIdentity: ProcessIdentity {
    public init() {}

    public var parentProcessID: pid_t { getppid() }
    public var userID: uid_t { getuid() }
    public var effectiveUserID: uid_t { geteuid() }
    public var groupID: gid_t { getgid() }
    public var effectiveGroupID: gid_t { getegid() }
    public var lastError: Int32 { errno }

    public func initializeGroups(name: String, groupID: gid_t) -> Int32 {
        initgroups(name, Int32(bitPattern: groupID))
    }

    public func setGroupID(_ groupID: gid_t) -> Int32 {
        setgid(groupID)
    }

    public func setUserID(_ userID: uid_t) -> Int32 {
        setuid(userID)
    }

    public func setEffectiveUserID(_ userID: uid_t) -> Int32 {
        seteuid(userID)
    }

    public func setEnvironment(_ name: String, _ value: String) {
        setenv(name, value, 1)
    }
}
