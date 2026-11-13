import Foundation
import GRDB
import HiveKit

/// How `NetworkAccess` is kept in the `hive` row, with the address in its own column.
enum StoredNetworkAccess: String {
    case thisMacOnly
    case address
    case allAddresses
}

/// The Hive's name and where it listens, kept in its one `hive` row.
public struct HiveSettingsStore: Sendable {
    let database: HiveDatabase
    /// Used until a port is chosen, and differs between the installed daemon and the development one.
    let defaultPort: Int

    public init(database: HiveDatabase, defaultPort: Int) {
        self.database = database
        self.defaultPort = defaultPort
    }

    public func settings() throws -> HiveSettings {
        try database.writer.read { database in
            let sql = "SELECT name, networkAccess, listenAddress, port, addressOptions, advertisesOnLocalNetwork FROM hive"
            guard let row = try Row.fetchOne(database, sql: sql) else {
                throw HiveDatabaseError.missingHiveID
            }
            return HiveSettings(
                name: row["name"],
                networkAccess: Self.networkAccess(kind: row["networkAccess"], address: row["listenAddress"]),
                port: row["port"] ?? defaultPort,
                addressOptions: try Self.addressOptions(from: row["addressOptions"]),
                advertisesOnLocalNetwork: row["advertisesOnLocalNetwork"]
            )
        }
    }

    /// Saves the settings with an audit entry for each one that changed, all or none of them.
    func save(_ new: HiveSettings, replacing old: HiveSettings, by deviceID: UUID, at date: Date) throws {
        let (kind, address) = Self.stored(new.networkAccess)
        let options = try Self.stored(new.addressOptions)
        try database.writer.write { database in
            try database.execute(
                sql: """
                UPDATE hive SET name = ?, networkAccess = ?, listenAddress = ?, port = ?, addressOptions = ?, advertisesOnLocalNetwork = ?
                """,
                arguments: [
                    new.name, kind.rawValue, address, new.port == old.port ? (try currentPort(in: database)) : new.port, options,
                    new.advertisesOnLocalNetwork,
                ]
            )
            for event in Self.changes(from: old, to: new) {
                try AuditLog.record(event, by: deviceID, at: date, in: database)
            }
        }
    }

    /// Keeps an unchosen port empty, so it stays the default.
    private func currentPort(in database: Database) throws -> Int? {
        try Int.fetchOne(database, sql: "SELECT port FROM hive")
    }

    static func changes(from old: HiveSettings, to new: HiveSettings) -> [AuditEvent] {
        var events: [AuditEvent] = []
        if old.name != new.name { events.append(.hiveRenamed(old: old.name, new: new.name)) }
        if old.networkAccess != new.networkAccess { events.append(.networkAccessChanged(old: old.networkAccess, new: new.networkAccess)) }
        if old.port != new.port { events.append(.portChanged(old: old.port, new: new.port)) }
        if old.addressOptions != new.addressOptions {
            events.append(.addressOptionsChanged(old: old.addressOptions, new: new.addressOptions))
        }
        if old.advertisesOnLocalNetwork != new.advertisesOnLocalNetwork {
            events.append(.localNetworkAdvertisingChanged(isOn: new.advertisesOnLocalNetwork))
        }
        return events
    }

    static func addressOptions(from json: String) throws -> [AddressOption] {
        try JSONDecoder().decode([AddressOption].self, from: Data(json.utf8))
    }

    static func stored(_ options: [AddressOption]) throws -> String {
        guard let json = String(bytes: try JSONEncoder().encode(options), encoding: .utf8) else {
            throw EncodingError.invalidValue(options, EncodingError.Context(codingPath: [], debugDescription: "Not UTF-8"))
        }
        return json
    }

    private static func networkAccess(kind: String, address: String?) -> NetworkAccess {
        switch StoredNetworkAccess(rawValue: kind) {
        case .address: address.map { .address($0) } ?? .thisMacOnly
        case .allAddresses: .allAddresses
        case .thisMacOnly, nil: .thisMacOnly
        }
    }

    private static func stored(_ access: NetworkAccess) -> (StoredNetworkAccess, String?) {
        switch access {
        case .thisMacOnly: (.thisMacOnly, nil)
        case .address(let address): (.address, address)
        case .allAddresses: (.allAddresses, nil)
        }
    }
}
