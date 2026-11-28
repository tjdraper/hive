#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import ScoutCore

/// The user Scout runs as. Root drops to it for good before touching Scout's state, since that user
/// owns the state folder and runs the code that talks to the network, so root can't trust what's in it.
enum ScoutUser {
    enum DropError: Error {
        case noUser
        case couldNotDrop(errno: Int32)
    }

    /// Does nothing when not run as root.
    static func dropRoot() throws(DropError) {
        guard geteuid() == 0 else { return }
        guard let entry = getpwnam(InstallLayout.server.user), entry.pointee.pw_uid != 0 else { throw .noUser }
        let (uid, gid) = (entry.pointee.pw_uid, entry.pointee.pw_gid)
        guard setgroups(0, nil) == 0, setgid(gid) == 0, setuid(uid) == 0 else { throw .couldNotDrop(errno: errno) }
        // Root can't be taken back.
        guard setuid(0) != 0, geteuid() == uid else { throw .couldNotDrop(errno: EPERM) }
    }

    static func message(for error: DropError) -> String {
        switch error {
        case .noUser: "There's no \(InstallLayout.server.user) user. Install Scout with sudo hive-scout install first."
        case .couldNotDrop(let errno): "Couldn't switch to the \(InstallLayout.server.user) user (errno \(errno))."
        }
    }
}
