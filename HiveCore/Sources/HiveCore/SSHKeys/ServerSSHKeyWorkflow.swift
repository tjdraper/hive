import Foundation
import HiveKit
import os

/// Showing Hive's SSH key for a server, and making a new one.
struct ServerSSHKeyWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "SSHKeys")

    let store: ServerSSHKeyStore
    let sealer: SecretSealer
    let settings: HiveSettingsStore
    /// The Hive Mac's addresses another machine could see, read fresh each time.
    let addresses: @Sendable () -> [NetworkInterfaceAddress]
    let now: @Sendable () -> Date

    /// Nil when no server has that ID, or the server has no key yet.
    func key(forServer id: UUID) throws -> ServerSSHKey? {
        try store.publicKey(forServer: id).map(serverSSHKey)
    }

    /// The server needs the new key in its `authorized_keys` before Hive can connect again. Returns nil
    /// when no server has that ID.
    func makeNewKey(forServer id: UUID, by deviceID: UUID) throws -> ServerSSHKey? {
        let key = try SealedSSHKey(SSHKeyPair(), sealer: sealer)
        guard let replacement = try store.replaceKey(forServer: id, with: key, by: deviceID, at: now()) else { return nil }
        let reasons = ConfirmationRequirement.reasons(replacingSSHKey: replacement.old)
        Self.logger.notice("Made a new SSH key for a server (to confirm: \(ConfirmationRequirement.logged(reasons), privacy: .public))")
        return try serverSSHKey(replacement.new)
    }

    private func serverSSHKey(_ key: OpenSSHPublicKey) throws -> ServerSSHKey {
        try ServerSSHKey(
            publicKey: key.line,
            fingerprint: key.fingerprint,
            comment: "Hive \(settings.settings().name)",
            macAddresses: addresses()
        )
    }
}
