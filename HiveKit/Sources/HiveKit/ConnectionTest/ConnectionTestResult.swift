import Foundation

/// What happened when Hive connected to a server with its key and ran a command that changes nothing.
public struct ConnectionTestResult: Codable, Hashable, Sendable {
    /// Nil when it connected.
    public let failure: ConnectionFailure?
    public let seconds: Double

    public init(failure: ConnectionFailure?, seconds: Double) {
        self.failure = failure
        self.seconds = seconds
    }
}

/// Why Hive couldn't reach a server over SSH, or didn't try.
public enum ConnectionFailure: String, Codable, Hashable, Sendable {
    /// The server has no SSH key of Hive's yet.
    case noSSHKey
    /// Hive connects only once a device has confirmed the server's host key.
    case noConfirmedHostKey
    /// The server answered with a host key other than the confirmed one. Hive refuses to go on.
    case hostKeyChanged
    /// The server turned down Hive's key, usually because it isn't in `authorized_keys`.
    case loginRefused
    /// The host couldn't be found or didn't answer.
    case unreachable
    /// The connection stopped answering part way.
    case stalled
    /// Anything else, such as the command failing on the server.
    case failed
}
