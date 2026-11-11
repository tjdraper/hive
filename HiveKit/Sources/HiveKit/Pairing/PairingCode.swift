import Foundation

/// What a new device needs to pair with a Hive, as text to copy or a QR code. It carries the key pin,
/// so the device trusts no network for the Hive's key, which is also why it's too long to type.
public struct PairingCode: Hashable, Sendable {
    public static let tokenLength = 16
    static let prefix = "hive1:"
    private static let version: UInt8 = 1
    /// More than any Hive needs, and few enough that a code stays scannable.
    public static let largestAddressCount = 8
    public static let longestHost = 253

    public let hiveID: UUID
    public let pin: PublicKeyPin
    /// Single-use, and only good while the window it came from is open.
    public let token: Data
    /// In the order to try them.
    public let addresses: [HiveAddress]

    public init(hiveID: UUID, pin: PublicKeyPin, token: Data, addresses: [HiveAddress]) {
        self.hiveID = hiveID
        self.pin = pin
        self.token = token
        self.addresses = addresses
    }

    /// The version, the Hive ID, the pin and the token, then each address's port, host length and host,
    /// in base64url after `prefix`.
    public var text: String {
        var bytes = Data([Self.version])
        withUnsafeBytes(of: hiveID.uuid) { bytes.append(contentsOf: $0) }
        bytes.append(pin.sha256)
        bytes.append(token)
        let addresses = addresses.prefix(Self.largestAddressCount)
        bytes.append(UInt8(addresses.count))
        for address in addresses {
            let host = Data(address.host.utf8.prefix(Self.longestHost))
            bytes.append(contentsOf: [UInt8(address.port >> 8 & 0xFF), UInt8(address.port & 0xFF), UInt8(host.count)])
            bytes.append(host)
        }
        return Self.prefix + bytes.base64URLEncoded
    }

    /// Nil for anything that isn't a whole code. Spaces and line breaks, such as from a message that
    /// wrapped it, are ignored.
    public init?(text: String) {
        let compact = text.filter { !$0.isWhitespace }
        guard compact.hasPrefix(Self.prefix),
              let data = Data(base64URLEncoded: String(compact.dropFirst(Self.prefix.count)))
        else { return nil }
        var reader = ByteReader(bytes: [UInt8](data))

        guard reader.read(1) == [Self.version],
              let uuid = reader.read(16),
              let pin = reader.read(32),
              let token = reader.read(Self.tokenLength),
              let count = reader.read(1)?.first,
              (1 ... Self.largestAddressCount).contains(Int(count))
        else { return nil }

        var addresses: [HiveAddress] = []
        for _ in 0 ..< count {
            guard let port = reader.read(2), let length = reader.read(1)?.first, length > 0,
                  let hostBytes = reader.read(Int(length)),
                  let host = String(bytes: hostBytes, encoding: .utf8)
            else { return nil }
            let portNumber = Int(port[0]) << 8 | Int(port[1])
            guard portNumber > 0 else { return nil }
            addresses.append(HiveAddress(host: host, port: portNumber))
        }
        guard reader.isAtEnd else { return nil }

        let hiveID = uuid.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
        self.init(hiveID: hiveID, pin: PublicKeyPin(sha256: Data(pin)), token: Data(token), addresses: addresses)
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

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded text: String) {
        guard text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
