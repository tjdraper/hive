import Foundation
import HiveKit

/// Every `ssh` Hive runs is built here, so each one checks the host key the same way and uses only
/// Hive's own key.
enum SSHCommand {
    static let connectTimeoutSeconds = 15
    /// With `serverAliveCountMax`, a connection that stops answering ends after about a minute.
    static let serverAliveIntervalSeconds = 15
    static let serverAliveCountMax = 4

    /// The options, for `ssh` itself and for programs such as `rsync` that run it.
    static func options(for target: SSHTarget, in directory: SSHRunDirectory) -> [String] {
        // No user or system config applies, so nothing in `~/.ssh/config` can loosen these.
        var arguments = ["-F", "/dev/null"]
        let options: [(String, String)] = [
            ("BatchMode", "yes"),
            ("StrictHostKeyChecking", "yes"),
            ("UserKnownHostsFile", directory.knownHosts.fileSystemPath),
            ("GlobalKnownHostsFile", "/dev/null"),
            ("HostKeyAlias", target.hostKeyAlias),
            ("CheckHostIP", "no"),
            ("UpdateHostKeys", "no"),
            ("VerifyHostKeyDNS", "no"),
            ("IdentitiesOnly", "yes"),
            ("IdentityFile", directory.identity.fileSystemPath),
            ("IdentityAgent", directory.agentSocket.fileSystemPath),
            ("PreferredAuthentications", "publickey"),
            ("PasswordAuthentication", "no"),
            ("KbdInteractiveAuthentication", "no"),
            ("ConnectTimeout", String(connectTimeoutSeconds)),
            ("ServerAliveInterval", String(serverAliveIntervalSeconds)),
            ("ServerAliveCountMax", String(serverAliveCountMax)),
            ("ForwardAgent", "no"),
            ("ForwardX11", "no"),
            ("ClearAllForwardings", "yes"),
            ("PermitLocalCommand", "no"),
            ("ControlMaster", "no"),
            ("ControlPath", "none"),
            ("RequestTTY", "no"),
            ("LogLevel", "ERROR"),
        ]
        for (name, value) in options {
            arguments += ["-o", "\(name)=\(value)"]
        }
        arguments += ["-p", String(target.connection.port), "-l", target.connection.user]
        return arguments
    }

    /// `remoteCommand` is run by the server's shell, so anything in it from outside Hive has to be quoted.
    static func arguments(for target: SSHTarget, in directory: SSHRunDirectory, remoteCommand: String) -> [String] {
        // `--` keeps a host from being read as an option, though the checks already refuse a leading `-`.
        options(for: target, in: directory) + ["--", target.connection.host, remoteCommand]
    }
}
