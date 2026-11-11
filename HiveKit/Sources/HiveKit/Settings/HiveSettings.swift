/// Sent whole to change any of them. Hive records each one that changed in the audit log.
public struct HiveSettings: Codable, Hashable, Sendable {
    public var name: String
    public var networkAccess: NetworkAccess
    public var port: Int
    /// Where other devices reach the Hive, in the order they try them. A pairing code carries them, and
    /// paired devices pick up changes, so they follow the Hive to a new port.
    public var addressOptions: [AddressOption]

    public init(name: String, networkAccess: NetworkAccess, port: Int, addressOptions: [AddressOption] = []) {
        self.name = name
        self.networkAccess = networkAccess
        self.port = port
        self.addressOptions = addressOptions
    }

    public var addresses: HiveAddresses {
        HiveAddresses(port: port, options: addressOptions.map { HiveAddress(host: $0.host, port: $0.port ?? port) })
    }
}

/// An address another device can reach the Hive at, such as its LAN address, its MagicDNS name or a
/// public hostname.
public struct AddressOption: Codable, Hashable, Sendable {
    /// An IP address or a DNS name.
    public var host: String
    /// Nil to follow the Hive's own port. A port forward or a tunnel can reach Hive on another.
    public var port: Int?

    public init(host: String, port: Int? = nil) {
        self.host = host
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
    /// Hosts Hive found that other devices could reach it at, such as its MagicDNS name, for adding to
    /// `HiveSettings.addressOptions`. Each is only any use while Hive listens on its address.
    public let suggestedHosts: [SuggestedHost]

    public init(settings: HiveSettings, interfaces: [NetworkInterfaceAddress], listeningOn: [String], suggestedHosts: [SuggestedHost]) {
        self.settings = settings
        self.interfaces = interfaces
        self.listeningOn = listeningOn
        self.suggestedHosts = suggestedHosts
    }
}

public struct NetworkInterfaceAddress: Codable, Hashable, Sendable {
    /// The BSD name, such as `en0` or `utun4`.
    public let interface: String
    public let address: String
    /// What the interface is, such as Wi-Fi, or Tailscale for Tailscale's. Nil when Hive can't tell,
    /// as for Docker's and virtual machines' bridges.
    public var displayName: String?
    /// The name a reverse lookup gives the address, such as a Tailscale address's MagicDNS name.
    public var hostName: String?

    public init(interface: String, address: String, displayName: String? = nil, hostName: String? = nil) {
        self.interface = interface
        self.address = address
        self.displayName = displayName
        self.hostName = hostName
    }
}

/// A host Hive suggests as an address option, with what it is, such as "Tailscale name".
public struct SuggestedHost: Codable, Hashable, Sendable {
    public let host: String
    public let label: String
    /// The Mac's address it reaches Hive at, or nil for a name that reaches it at any of them, such as
    /// the Mac's Bonjour name, which is only any use while Hive listens on all of them.
    public let address: String?

    public init(host: String, label: String, address: String?) {
        self.host = host
        self.label = label
        self.address = address
    }

    /// Whether another device could reach Hive at it while Hive listens as `access` says.
    public func isReachable(through access: NetworkAccess) -> Bool {
        switch access {
        case .thisMacOnly: false
        case .address(let chosen): address == chosen
        case .allAddresses: true
        }
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
    /// An address option that isn't an IP address or DNS name another device could reach, has a port
    /// outside 1–65535, or repeats another.
    case invalidAddressOption
    case tooManyAddressOptions
}
