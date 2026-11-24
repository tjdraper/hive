import HiveKit

extension Server {
    /// Where the setup steps say Hive connects. They're shown only once a server has SSH details.
    var setupConnection: ServerConnection {
        connection ?? .empty
    }
}
