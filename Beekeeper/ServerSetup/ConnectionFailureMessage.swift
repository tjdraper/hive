import HiveKit

extension ConnectionFailure {
    /// Why Hive couldn't reach `server`, for the person setting it up.
    func message(for server: Server) -> String {
        let connection = server.connection
        let user = connection?.user ?? "the SSH user"
        let host = connection.map { "\($0.host) on port \($0.port)" } ?? "the server"
        return switch self {
        case .noSSHDetails:
            "Hive has no SSH details for this server yet."
        case .noSSHKey:
            "This server has no key of Hive's yet."
        case .noConfirmedHostKey:
            "Confirm the server's host key first."
        case .hostKeyChanged:
            "The server showed a host key other than the confirmed one, so Hive didn't sign in. Either its key "
                + "was replaced, or another machine is answering in its place."
        case .loginRefused:
            "The server turned down Hive's key. Check that the line is in \(user)'s authorized_keys, and "
                + "that any addresses it's limited to include the one the server sees Hive connect from."
        case .unreachable:
            "Couldn't reach \(host). Check the host and port, and that the "
                + "Hive's Mac can reach the server."
        case .stalled:
            "The server stopped answering partway through."
        case .failed:
            "The connection failed for a reason Hive couldn't tell."
        }
    }
}
