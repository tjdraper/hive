/// The line a server's `authorized_keys` needs for Hive's key.
enum AuthorizedKeysLine {
    /// `restrict` turns off forwarding, terminals and `~/.ssh/rc`, none of which Hive uses. `rsync` and
    /// `docker exec` without `-t` still run.
    static func line(for key: OpenSSHPublicKey, comment: String, from addresses: [String] = []) -> String {
        let options = addresses.isEmpty ? "restrict" : "restrict,from=\"\(addresses.joined(separator: ","))\""
        return "\(options) \(key.line) \(comment)"
    }

    /// Names the Hive, so the line can be recognized on a server several Hives back up.
    static func comment(hiveName: String) -> String {
        "Hive \(hiveName)"
    }
}
