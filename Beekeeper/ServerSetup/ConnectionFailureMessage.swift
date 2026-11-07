import HiveKit

extension ConnectionFailure {
    /// Why Hive couldn't reach `server`, for the person setting it up.
    func message(for server: Server) -> String {
        let connection = server.connection
        return switch self {
        case .noSSHKey:
            "This server has no key of Hive's yet."
        case .noConfirmedHostKey:
            "Confirm the server's host key first."
        case .hostKeyChanged:
            "The server showed a host key other than the confirmed one, so Hive didn't sign in. Either its key "
                + "was replaced, or another machine is answering in its place."
        case .loginRefused:
            "The server turned down Hive's key. Check that the line is in \(connection.user)'s authorized_keys, and "
                + "that any addresses it's limited to include the one the server sees Hive connect from."
        case .unreachable:
            "Couldn't reach \(connection.host) on port \(connection.port). Check the host and port, and that the "
                + "Hive's Mac can reach the server."
        case .stalled:
            "The server stopped answering partway through."
        case .failed:
            "The connection failed for a reason Hive couldn't tell."
        }
    }
}
