import Foundation

/// How a Hive advertises itself with Bonjour (§15), so a device on the same local network finds where
/// to reach it. Nothing advertised is trusted: anyone on the network can advertise any Hive ID, and a
/// device only ever talks to the key it pinned when it paired.
public enum LocalNetworkService {
    public static let type = "_hive._tcp"
    /// DNS-SD instance names are at most 63 bytes.
    static let longestName = 63
    private static let hiveIDKey = "hive"

    /// The Hive's name, cut to fit on a character boundary.
    public static func instanceName(for hiveName: String) -> String {
        var name = ""
        for character in hiveName {
            guard name.utf8.count + character.utf8.count <= longestName else { break }
            name.append(character)
        }
        return name
    }

    /// One `hive=<ID>` entry, length-prefixed as DNS-SD TXT records are (RFC 6763 §6).
    public static func txtRecord(hiveID: UUID) -> Data {
        let entry = Data("\(hiveIDKey)=\(hiveID.uuidString)".utf8)
        return Data([UInt8(entry.count)]) + entry
    }

    /// Nil when the record names no Hive ID.
    public static func hiveID(inTXTRecord record: Data) -> UUID? {
        let bytes = [UInt8](record)
        var offset = 0
        while offset < bytes.count {
            let length = Int(bytes[offset])
            let start = offset + 1
            guard start + length <= bytes.count else { return nil }
            let entry = String(bytes: bytes[start ..< start + length], encoding: .utf8) ?? ""
            let parts = entry.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == hiveIDKey {
                return UUID(uuidString: String(parts[1]))
            }
            offset = start + length
        }
        return nil
    }
}
