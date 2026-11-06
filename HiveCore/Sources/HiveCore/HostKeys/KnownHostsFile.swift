/// Hive's `known_hosts`, written for each connection from the host key a device confirmed. It holds
/// only that server's key, so the server's connection can't match another server's entry.
enum KnownHostsFile {
    static func contents(for target: SSHTarget) -> String {
        "\(target.hostKeyAlias) \(target.hostKey.line)\n"
    }
}
