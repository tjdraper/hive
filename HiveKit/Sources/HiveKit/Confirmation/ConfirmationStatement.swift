import CryptoKit
import Foundation

/// What a device's confirmation key signs: one request, whole. The method and path name the action and
/// what it acts on, and the body's hash says exactly what it changes, so a signature can't be used for
/// any other request, object or change, or twice, since Hive accepts each nonce once.
public enum ConfirmationStatement {
    /// The request as it's sent, which Hive reads back as it arrives.
    public struct Request: Sendable {
        public let method: String
        public let path: String
        /// Empty for a request without one.
        public let body: Data

        public init(method: String, path: String, body: Data) {
            self.method = method
            self.path = path
            self.body = body
        }
    }

    private static let label = Data("Hive confirmation v1".utf8)

    public static func bytes(hiveID: UUID, deviceID: UUID, nonce: Data, request: Request) -> Data {
        var bytes = label
        bytes.append(0)
        bytes.append(contentsOf: uuidBytes(hiveID))
        bytes.append(contentsOf: uuidBytes(deviceID))
        // Each variable part carries its length, so no two requests can produce the same bytes.
        for part in [nonce, Data(request.method.utf8), Data(request.path.utf8)] {
            withUnsafeBytes(of: UInt32(part.count).bigEndian) { bytes.append(contentsOf: $0) }
            bytes.append(part)
        }
        bytes.append(contentsOf: SHA256.hash(data: request.body))
        return bytes
    }

    private static func uuidBytes(_ uuid: UUID) -> [UInt8] {
        withUnsafeBytes(of: uuid.uuid) { Array($0) }
    }
}
