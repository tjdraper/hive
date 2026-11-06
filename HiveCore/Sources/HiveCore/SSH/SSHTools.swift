import Foundation

/// The Mac's own OpenSSH tools, run by their full paths so nothing on `PATH` stands in for them.
struct SSHTools: Sendable {
    var ssh = URL(filePath: "/usr/bin/ssh")
    var keyscan = URL(filePath: "/usr/bin/ssh-keyscan")
    var agent = URL(filePath: "/usr/bin/ssh-agent")
    var add = URL(filePath: "/usr/bin/ssh-add")

    /// Nothing else from the daemon's environment reaches them, such as an `SSH_AUTH_SOCK` for another
    /// agent. The C locale keeps their messages in the English `SSHFailureReader` reads.
    static func environment(adding extra: [String: String] = [:]) -> [String: String] {
        var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
        if let home = ProcessInfo.processInfo.environment["HOME"] { environment["HOME"] = home }
        return environment.merging(extra) { $1 }
    }
}
