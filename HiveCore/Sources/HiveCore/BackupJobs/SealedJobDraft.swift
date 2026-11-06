import Foundation
import HiveKit

/// A checked job draft with its new passwords sealed and taken out of the draft, ready to store.
struct SealedJobDraft {
    let draft: BackupJobDraft
    /// One for each of the draft's databases: its new password, or nil to keep the one it has.
    let newPasswords: [SealedSecret?]

    init(_ draft: BackupJobDraft, sealer: SecretSealer) throws {
        newPasswords = try draft.databases.map { database in
            try database.password.map { try sealer.seal(Data($0.utf8)) }
        }
        var withoutPasswords = draft
        withoutPasswords.databases = draft.databases.map { database in
            BackupDatabaseDraft(id: database.id, settings: database.settings, password: nil)
        }
        self.draft = withoutPasswords
    }

    /// The positions of the databases a new password was entered for.
    var passwordPositions: [Int] {
        newPasswords.indices.filter { newPasswords[$0] != nil }
    }
}
