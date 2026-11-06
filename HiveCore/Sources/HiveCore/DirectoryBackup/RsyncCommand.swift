import Foundation

/// Every rsync Hive runs is built here.
enum RsyncCommand {
    /// rsync's own limit on time without any data moving. It sends keepalives while it works through a
    /// large tree, so only a stalled transfer reaches it.
    static let timeoutSeconds = 300

    /// rsync passes the source path to the server through its protocol rather than the server's shell,
    /// so nothing in it is ever read as shell syntax.
    private static let common = ["--secluded-args", "--timeout=\(timeoutSeconds)"]

    /// Lists the top of a directory without copying anything, to tell a missing or empty one apart
    /// before any snapshot is made.
    static func list() -> [String] {
        ["--list-only"] + common
    }

    /// Never `--inplace` or `--append`: an unchanged file in a snapshot is a hard link shared with
    /// earlier snapshots, and either would change it in all of them (§9). rsync writes a changed file
    /// to a new one and renames it over, which leaves the shared one alone.
    static func pull(linkingTo previous: URL?) -> [String] {
        var arguments = ["--archive", "--delete", "--stats", "--no-human-readable"] + common
        // Hive runs as a normal user and can't set owners, so --fake-super keeps them, and modes it
        // can't apply, in an extended attribute on each file. --numeric-ids keeps the server's IDs
        // rather than mapping them to whichever accounts on the Mac share their names.
        arguments += ["--fake-super", "--numeric-ids"]
        if let previous {
            arguments.append("--link-dest=\(previous.fileSystemPath)/")
        }
        return arguments
    }

    /// The trailing slash names what's in the folder rather than the folder itself.
    static func contentsPath(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    /// rsync reads `[address]:path` for an IPv6 address, which would otherwise be split at its first colon.
    static func remoteSource(host: String, path: String) -> String {
        let host = host.contains(":") ? "[\(host)]" : host
        return "\(host):\(contentsPath(path))"
    }
}
