import Foundation
import Security

enum DeviceKeychainError: Error, Equatable {
    case couldNotSave(OSStatus)
    case couldNotRead(OSStatus)
    case unreadable
}

/// Beekeeper's credential for each Hive, in the data protection keychain under Beekeeper's own access
/// group. A Secure Enclave key's saved form works for any program on the device, so on the Mac it can't
/// be in a file the user's other programs could read. The access group is a restricted entitlement:
/// only a program signed by Beekeeper's team, with a provisioning profile Apple issued for it, gets in.
struct DeviceKeychain {
    private static let service = "Hive device key"

    func save(_ credential: DeviceCredential) throws {
        let data = try JSONEncoder().encode(credential)
        try delete(hiveID: credential.hiveID)

        var attributes = Self.query(hiveID: credential.hiveID)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw DeviceKeychainError.couldNotSave(status) }
    }

    func credential(for hiveID: UUID) throws -> DeviceCredential? {
        var query = Self.query(hiveID: hiveID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw DeviceKeychainError.couldNotRead(status) }
        guard let data = result as? Data,
              let credential = try? JSONDecoder().decode(DeviceCredential.self, from: data)
        else { throw DeviceKeychainError.unreadable }
        return credential
    }

    func delete(hiveID: UUID) throws {
        let status = SecItemDelete(Self.query(hiveID: hiveID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DeviceKeychainError.couldNotSave(status) }
    }

    /// Without an access group, items go in the first one Beekeeper's entitlement lists, its own. Never
    /// synced: each device pairs on its own.
    private static func query(hiveID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hiveID.uuidString,
        ]
    }
}
