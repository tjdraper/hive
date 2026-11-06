import Foundation

/// What a device signs to sign in. It names the Hive and the device as well as the challenge, so a
/// signature can only ever mean this device signing in to this Hive.
public enum SignInStatement {
    private static let label = Data("Hive sign-in v1".utf8)

    public static func bytes(hiveID: UUID, deviceID: UUID, challenge: Data) -> Data {
        var bytes = label
        bytes.append(0)
        bytes.append(contentsOf: uuidBytes(hiveID))
        bytes.append(contentsOf: uuidBytes(deviceID))
        bytes.append(challenge)
        return bytes
    }

    private static func uuidBytes(_ uuid: UUID) -> [UInt8] {
        withUnsafeBytes(of: uuid.uuid) { Array($0) }
    }
}
