#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// What a Scout needs to enroll with a Hive for one server, as text pasted into `hive-scout enroll`.
/// It carries the pin of Hive's key, so Scout trusts no network for it.
public struct EnrollmentCode: Hashable, Sendable {
    public struct Address: Codable, Hashable, Sendable {
        public let host: String
        public let port: Int

        public init(host: String, port: Int) {
            self.host = host
            self.port = port
        }
    }

    public static let tokenLength = 16
    public static let pinLength = 32
    /// As many as a pairing code holds.
    public static let largestAddressCount = 8
    public static let longestHost = 253
    static let prefix = "scout1:"
    private static let version: UInt8 = 1

    public let hiveID: UUID
    /// The server the Scout reports for.
    public let serverID: UUID
    /// The SHA-256 hash of Hive's identity key in its X9.63 form.
    public let pin: Data
    /// Single-use, and only good while the server's enrollment window is open.
    public let token: Data
    /// In the order to try them.
    public let addresses: [Address]

    public init(hiveID: UUID, serverID: UUID, pin: Data, token: Data, addresses: [Address]) {
        self.hiveID = hiveID
        self.serverID = serverID
        self.pin = pin
        self.token = token
        self.addresses = addresses
    }

    /// The version, the Hive ID, the server ID, the pin and the token, then each address's port, host
    /// length and host, in base64url after `prefix`.
    public var text: String {
        var bytes = Data([Self.version])
        withUnsafeBytes(of: hiveID.uuid) { bytes.append(contentsOf: $0) }
        withUnsafeBytes(of: serverID.uuid) { bytes.append(contentsOf: $0) }
        bytes.append(pin)
        bytes.append(token)
        let addresses = addresses.prefix(Self.largestAddressCount)
        bytes.append(UInt8(addresses.count))
        for address in addresses {
            let host = Data(address.host.utf8.prefix(Self.longestHost))
            bytes.append(contentsOf: [UInt8(address.port >> 8 & 0xFF), UInt8(address.port & 0xFF), UInt8(host.count)])
            bytes.append(host)
        }
        let base64URL = bytes.base64EncodedString().compactMap { character -> Character? in
            switch character {
            case "+": "-"
            case "/": "_"
            case "=": nil
            default: character
            }
        }
        return Self.prefix + String(base64URL)
    }

    /// Nil for anything that isn't a whole code. Spaces and line breaks, such as from a terminal that
    /// wrapped it, are ignored.
    public init?(text: String) {
        let compact = text.filter { !$0.isWhitespace }
        guard compact.hasPrefix(Self.prefix), let data = Self.data(base64URL: compact.dropFirst(Self.prefix.count)) else { return nil }
        var reader = ByteReader(bytes: [UInt8](data))

        guard reader.read(1) == [Self.version],
              let hiveID = reader.read(16).map(Self.uuid),
              let serverID = reader.read(16).map(Self.uuid),
              let pin = reader.read(Self.pinLength),
              let token = reader.read(Self.tokenLength),
              let count = reader.read(1)?.first,
              (1 ... Self.largestAddressCount).contains(Int(count))
        else { return nil }

        var addresses: [Address] = []
        for _ in 0 ..< count {
            guard let port = reader.read(2), let length = reader.read(1)?.first, length > 0,
                  let hostBytes = reader.read(Int(length)),
                  let host = String(validating: hostBytes, as: UTF8.self)
            else { return nil }
            let portNumber = Int(port[0]) << 8 | Int(port[1])
            guard portNumber > 0 else { return nil }
            addresses.append(Address(host: host, port: portNumber))
        }
        guard reader.isAtEnd else { return nil }
        self.init(hiveID: hiveID, serverID: serverID, pin: Data(pin), token: Data(token), addresses: addresses)
    }

    private static func uuid(_ bytes: [UInt8]) -> UUID {
        bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }

    private static func data(base64URL text: Substring) -> Data? {
        guard text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        var base64 = String(text.map { $0 == "-" ? "+" : $0 == "_" ? "/" : $0 })
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}

private struct ByteReader {
    let bytes: [UInt8]
    var offset = 0

    var isAtEnd: Bool {
        offset == bytes.count
    }

    mutating func read(_ count: Int) -> [UInt8]? {
        guard count <= bytes.count - offset else { return nil }
        defer { offset += count }
        return Array(bytes[offset ..< offset + count])
    }
}
