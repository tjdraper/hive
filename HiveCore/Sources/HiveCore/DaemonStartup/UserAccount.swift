import Darwin
import Foundation

public struct UserAccount: Equatable, Sendable {
    public let userID: uid_t
    public let groupID: gid_t
    public let name: String
    public let homeDirectory: URL

    public init(userID: uid_t, groupID: gid_t, name: String, homeDirectory: URL) {
        self.userID = userID
        self.groupID = groupID
        self.name = name
        self.homeDirectory = homeDirectory
    }
}

public protocol UserAccountFinding {
    func account(for userID: uid_t) -> UserAccount?
}

public struct UserAccountDirectory: UserAccountFinding {
    public init() {}

    public func account(for userID: uid_t) -> UserAccount? {
        let suggestedSize = sysconf(Int32(_SC_GETPW_R_SIZE_MAX))
        var buffer = [CChar](repeating: 0, count: suggestedSize > 0 ? suggestedSize : 16_384)
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?

        // The entry's strings point into the buffer, so they're copied out before it goes away.
        return buffer.withUnsafeMutableBufferPointer { storage in
            guard getpwuid_r(userID, &entry, storage.baseAddress, storage.count, &result) == 0,
                  result != nil,
                  let name = entry.pw_name,
                  let home = entry.pw_dir
            else { return nil }

            return UserAccount(
                userID: entry.pw_uid,
                groupID: entry.pw_gid,
                name: String(cString: name),
                homeDirectory: URL(filePath: String(cString: home), directoryHint: .isDirectory)
            )
        }
    }
}
