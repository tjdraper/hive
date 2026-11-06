import Darwin
import Foundation

enum SSHRunDirectoryError: Error, Equatable {
    case couldNotCreate(errno: Int32)
}

/// A folder only Hive's user can open, made for one connection and removed after it. It holds the
/// agent's socket, the server's `known_hosts` line and the public half of Hive's key, none of them secret.
struct SSHRunDirectory {
    let url: URL

    /// In the user's own temporary folder rather than the data directory, since a socket's path can't be
    /// longer than 104 bytes and a long user name could push the data directory's past it.
    static func make() throws -> SSHRunDirectory {
        try make(in: userTemporaryDirectory())
    }

    static func make(in parent: URL) throws -> SSHRunDirectory {
        // mkdtemp creates the folder 0700, with a name nobody else can claim first.
        var template = Array(parent.appending(path: "hive-ssh.XXXXXX").fileSystemPath.utf8CString)
        guard template.withUnsafeMutableBufferPointer({ mkdtemp($0.baseAddress) }) != nil else {
            throw SSHRunDirectoryError.couldNotCreate(errno: errno)
        }
        guard let path = String(validating: template.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self) else {
            throw SSHRunDirectoryError.couldNotCreate(errno: EILSEQ)
        }
        return SSHRunDirectory(url: URL(filePath: path, directoryHint: .isDirectory))
    }

    /// Read at each use, since the daemon starts as root and only later becomes its user.
    private static func userTemporaryDirectory() -> URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count) > 0,
              let path = String(validating: buffer.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
        else { return URL(filePath: "/tmp", directoryHint: .isDirectory) }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    var agentSocket: URL {
        url.appending(path: "agent", directoryHint: .notDirectory)
    }

    var knownHosts: URL {
        url.appending(path: "known_hosts", directoryHint: .notDirectory)
    }

    /// `ssh` finds the matching private key in the agent.
    var identity: URL {
        url.appending(path: "identity.pub", directoryHint: .notDirectory)
    }

    func write(knownHosts: String, identity: String) throws {
        try Data(knownHosts.utf8).write(to: self.knownHosts, options: .withoutOverwriting)
        try Data((identity + "\n").utf8).write(to: self.identity, options: .withoutOverwriting)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
