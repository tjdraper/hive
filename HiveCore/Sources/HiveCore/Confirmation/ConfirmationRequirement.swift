import Foundation
import HiveKit

/// Which changes need the device's confirmation key as well as its session (§6). Each is checked against
/// the stored values inside the change's write transaction, so a change made in between can't slip through.
enum ConfirmationRequirement {
    static func reasons(from old: Server, to new: Server) -> Set<ConfirmationReason> {
        var reasons: Set<ConfirmationReason> = []
        if old.connection != new.connection { reasons.insert(.connectionChanged) }
        if isLower(new.quotaBytes, than: old.quotaBytes) { reasons.insert(.quotaLowered) }
        return reasons
    }

    /// `passwordsEnteredAt` are positions in `new.databases`. A password entered for a database that had
    /// none replaces nothing, so it needs no confirmation.
    static func reasons(from old: BackupJob, to new: BackupJob, passwordsEnteredAt: [Int]) -> Set<ConfirmationReason> {
        var reasons: Set<ConfirmationReason> = []
        if new.retention.dailySnapshots < old.retention.dailySnapshots || new.retention.monthlySnapshots < old.retention.monthlySnapshots {
            reasons.insert(.retentionLowered)
        }
        let hadPasswords = Set(old.databases.filter(\.hasPassword).map(\.id))
        if passwordsEnteredAt.contains(where: { hadPasswords.contains(new.databases[$0].id) }) {
            reasons.insert(.passwordReplaced)
        }
        return reasons
    }

    /// Recording a server's first host key needs nothing, but replacing one could let Hive connect to
    /// another machine.
    static func reasons(replacingHostKey old: OpenSSHPublicKey?, with new: OpenSSHPublicKey) -> Set<ConfirmationReason> {
        old == nil || old == new ? [] : [.hostKeyReplaced]
    }

    /// A server's first key replaces nothing.
    static func reasons(replacingSSHKey old: OpenSSHPublicKey?) -> Set<ConfirmationReason> {
        old == nil ? [] : [.sshKeyReplaced]
    }

    /// Throws `ConfirmationError.required` when a change needing confirmation wasn't confirmed, which
    /// rolls back the transaction it's called from.
    static func check(_ reasons: Set<ConfirmationReason>, isConfirmed: Bool) throws {
        if !reasons.isEmpty, !isConfirmed { throw ConfirmationError.required(reasons) }
    }

    /// For the system log, which holds kinds but never values.
    static func logged(_ reasons: Set<ConfirmationReason>) -> String {
        reasons.isEmpty ? "none" : reasons.map(\.rawValue).sorted().joined(separator: ", ")
    }

    /// No quota is the highest.
    private static func isLower(_ new: Int64?, than old: Int64?) -> Bool {
        switch (old, new) {
        case (nil, .some): true
        case (.some(let old), .some(let new)): new < old
        case (_, nil): false
        }
    }
}
