import Foundation

/// The public half of Hive's SSH key for one server, to add to the server's `authorized_keys`. The
/// private half never leaves Hive.
public struct ServerSSHKey: Codable, Hashable, Sendable {
    /// `ssh-ed25519` and the key, as OpenSSH writes it.
    public let publicKey: String
    public let fingerprint: String
    /// The line for `authorized_keys`, with `restrict`, which leaves Hive what it needs to run commands
    /// but no forwarding or terminal.
    public let authorizedKeysLine: String
    /// The same line, accepted only from the Hive Mac's current addresses. Nil when it has none
    /// another machine could see.
    public let restrictedAuthorizedKeysLine: String?

    public init(publicKey: String, fingerprint: String, authorizedKeysLine: String, restrictedAuthorizedKeysLine: String?) {
        self.publicKey = publicKey
        self.fingerprint = fingerprint
        self.authorizedKeysLine = authorizedKeysLine
        self.restrictedAuthorizedKeysLine = restrictedAuthorizedKeysLine
    }
}
