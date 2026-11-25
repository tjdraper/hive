import Foundation
import HiveKit

/// What a metrics card or page is about: one of the Hive's servers, or the Hive Mac, whose figures Hive
/// reads itself and keeps under the Hive's own ID.
struct MetricsSource: Hashable {
    let name: String
    let isHiveMac: Bool

    /// Nil for a server removed since its figures were read.
    init?(serverID: UUID, hive: KnownHive, servers: ServerList) {
        if serverID == hive.id {
            name = hive.name
            isHiveMac = true
        } else if let server = servers.server(serverID) {
            name = server.name
            isHiveMac = false
        } else {
            return nil
        }
    }

    /// For a page left open on a server that's since been removed.
    static let removedServer = MetricsSource(name: "Server", isHiveMac: false)

    init(name: String, isHiveMac: Bool) {
        self.name = name
        self.isHiveMac = isHiveMac
    }

    var systemImage: String {
        isHiveMac ? "desktopcomputer" : "server.rack"
    }
}
