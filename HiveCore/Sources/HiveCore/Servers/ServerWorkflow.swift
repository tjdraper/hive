import Foundation
import HiveKit
import os

/// Adding, changing and removing servers.
struct ServerWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Configuration")

    let store: ServerStore
    let sealer: SecretSealer
    let now: @Sendable () -> Date

    func add(_ draft: ServerDraft, by deviceID: UUID) throws -> Server {
        let draft = try ServerDraftCheck.validated(draft)
        let server = try store.add(draft, sshKey: SealedSSHKey(SSHKeyPair(), sealer: sealer), by: deviceID, at: now())
        Self.logger.notice("Added a server")
        return server
    }

    /// Returns nil when no server has that ID.
    func change(id: UUID, to draft: ServerDraft, isConfirmed: Bool, by deviceID: UUID) throws -> Server? {
        let draft = try ServerDraftCheck.validated(draft)
        guard let (old, new) = try store.change(id: id, to: draft, isConfirmed: isConfirmed, by: deviceID, at: now()) else { return nil }
        let changed = ServerStore.changes(from: old, to: new)
        if !changed.isEmpty {
            let reasons = ConfirmationRequirement.logged(ConfirmationRequirement.reasons(from: old, to: new))
            Self.logger.notice("Changed a server (\(changed.count, privacy: .public) changes, confirmed: \(reasons, privacy: .public))")
        }
        return new
    }

    func remove(id: UUID, by deviceID: UUID) throws -> Bool {
        guard try store.remove(id: id, by: deviceID, at: now()) != nil else { return false }
        Self.logger.notice("Removed a server and its jobs from the configuration")
        return true
    }
}
