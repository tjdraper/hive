import Foundation

/// The binary encoding OpenSSH uses inside keys (RFC 4251 §5): big-endian lengths before each string.
enum SSHWireFormat {
    static func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    static func string(_ bytes: Data) -> Data {
        uint32(UInt32(bytes.count)) + bytes
    }

    static func string(_ text: String) -> Data {
        string(Data(text.utf8))
    }

    /// The first string in `data`, which in a public key blob names the key's type.
    static func firstString(in data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        let length = data.prefix(4).reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, data.count >= 4 + length else { return nil }
        return String(data: data.dropFirst(4).prefix(length), encoding: .utf8)
    }
}
