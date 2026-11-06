/// Sent whole to change any of them. Hive records each one that changed in the audit log.
public struct HiveSettings: Codable, Hashable, Sendable {
    public var name: String
    public var networkAccess: NetworkAccess
    public var port: Int

    public init(name: String, networkAccess: NetworkAccess, port: Int) {
        self.name = name
        self.networkAccess = networkAccess
        self.port = port
    }
}

/// Where Hive listens besides `127.0.0.1`, which it always listens on so Beekeeper on the Hive Mac keeps working.
public enum NetworkAccess: Codable, Hashable, Sendable {
    case thisMacOnly
    /// One of the Mac's addresses, such as its Tailscale address. Hive listens on it whenever it's present,
    /// including when it appears after Hive starts. An address is kept rather than an interface name,
    /// since Tailscale's `utun` number can change between restarts and its address doesn't.
    case address(String)
    case allAddresses
}

/// The settings, and what Beekeeper needs to show and change them.
public struct HiveSettingsState: Codable, Hashable, Sendable {
    public let settings: HiveSettings
    /// The Mac's addresses that `NetworkAccess.address` can choose from.
    public let interfaces: [NetworkInterfaceAddress]
    /// The addresses Hive is listening on right now, `::` standing for all of them.
    public let listeningOn: [String]

    public init(settings: HiveSettings, interfaces: [NetworkInterfaceAddress], listeningOn: [String]) {
        self.settings = settings
        self.interfaces = interfaces
        self.listeningOn = listeningOn
    }
}

public struct NetworkInterfaceAddress: Codable, Hashable, Sendable {
    /// The BSD name, such as `en0` or `utun4`.
    public let interface: String
    public let address: String

    public init(interface: String, address: String) {
        self.interface = interface
        self.address = address
    }
}

/// Sent with 422 when Hive turns down a settings change, which then changes nothing.
public struct SettingsRefusal: Codable, Hashable, Sendable {
    public let problem: SettingsProblem

    public init(problem: SettingsProblem) {
        self.problem = problem
    }
}

public enum SettingsProblem: String, Codable, Hashable, Sendable {
    case invalidName
    /// Outside 1024–65535. Lower ports need root, which Hive gives up.
    case invalidPort
    /// Not an address another device could reach Hive at, such as a loopback or link-local one.
    case invalidAddress
    /// Something else is listening on that port on `127.0.0.1`.
    case portUnavailable
}
