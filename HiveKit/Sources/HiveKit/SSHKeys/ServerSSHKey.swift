import Foundation

/// The public half of Hive's SSH key for one server, to add to the server's `authorized_keys`. The
/// private half never leaves Hive.
public struct ServerSSHKey: Codable, Hashable, Sendable {
    /// `ssh-ed25519` and the key, as OpenSSH writes it.
    public let publicKey: String
    public let fingerprint: String
    /// Names the Hive, so the line can be recognized on a server several Hives back up.
    public let comment: String
    /// The Hive Mac's addresses another machine could see, read when this was sent, for choosing which
    /// ones the server accepts the key from.
    public let macAddresses: [NetworkInterfaceAddress]

    public init(publicKey: String, fingerprint: String, comment: String, macAddresses: [NetworkInterfaceAddress]) {
        self.publicKey = publicKey
        self.fingerprint = fingerprint
        self.comment = comment
        self.macAddresses = macAddresses
    }

    /// The line for `authorized_keys`, accepted only from `addresses` when there are any. `restrict`
    /// leaves Hive what it needs to run commands, `rsync` and `docker exec` without `-t`, but no
    /// forwarding, terminal or `~/.ssh/rc`.
    public func authorizedKeysLine(acceptingFrom addresses: [String] = []) -> String {
        let options = addresses.isEmpty ? "restrict" : "restrict,from=\"\(addresses.joined(separator: ","))\""
        return "\(options) \(publicKey) \(comment)"
    }
}
