import Foundation
import GRDB
import HiveKit

struct EmailSettingsRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "emailSettings"

    var singleton = 1
    var host: String
    var port: Int
    var security: String
    var username: String
    var senderAddress: String
    /// Kept as JSON, which GRDB does for a property that isn't a database value.
    var recipients: [String]
    var sealedPassword: Data?

    init(_ settings: EmailSettings, sealedPassword: Data?) {
        host = settings.host
        port = settings.port
        security = settings.security.rawValue
        username = settings.username
        senderAddress = settings.senderAddress
        recipients = settings.recipients
        self.sealedPassword = sealedPassword
    }

    var settings: EmailSettings {
        EmailSettings(
            host: host,
            port: port,
            security: EmailSecurity(rawValue: security) ?? .implicitTLS,
            username: username,
            senderAddress: senderAddress,
            recipients: recipients
        )
    }
}

/// What sending an email needs from the store.
struct StoredEmailSettings {
    let settings: EmailSettings
    let sealedPassword: SealedSecret?
}

/// The email settings in Hive's store. Each change is saved with its audit entries, all or none of them.
struct EmailSettingsStore: Sendable {
    let database: HiveDatabase

    func state() throws -> EmailSettingsState {
        let record = try database.writer.read { try EmailSettingsRecord.fetchOne($0) }
        return EmailSettingsState(settings: record?.settings, hasPassword: record?.sealedPassword != nil)
    }

    func stored() throws -> StoredEmailSettings? {
        try database.writer.read { database in
            try EmailSettingsRecord.fetchOne(database).map {
                StoredEmailSettings(settings: $0.settings, sealedPassword: $0.sealedPassword.map(SealedSecret.init(data:)))
            }
        }
    }

    /// `settings` have passed `EmailSettingsCheck`. A new host clears the password, unless `newPassword`
    /// replaces it, so it's never sent to the new host without being entered again. Throws
    /// `ConfirmationError.required`, changing nothing, when the change needs confirming and isn't confirmed.
    func save(
        _ settings: EmailSettings,
        newPassword: SealedSecret?,
        isConfirmed: Bool,
        by deviceID: UUID,
        at date: Date
    ) throws -> (old: EmailSettings?, new: EmailSettingsState) {
        try database.writer.write { database in
            let existing = try EmailSettingsRecord.fetchOne(database)
            let old = existing?.settings
            try ConfirmationRequirement.check(ConfirmationRequirement.reasons(from: old, to: settings), isConfirmed: isConfirmed)

            let keptPassword = old?.host == settings.host ? existing?.sealedPassword : nil
            let record = EmailSettingsRecord(settings, sealedPassword: newPassword?.data ?? keptPassword)
            try record.save(database)

            for change in Self.changes(from: old, to: settings, passwordEntered: newPassword != nil) {
                try AuditLog.record(.email(change), by: deviceID, at: date, in: database)
            }
            return (old, EmailSettingsState(settings: settings, hasPassword: record.sealedPassword != nil))
        }
    }

    /// Clears the settings and the password. Returns false when email wasn't set up.
    func turnOff(by deviceID: UUID, at date: Date) throws -> Bool {
        try database.writer.write { database in
            guard try EmailSettingsRecord.deleteAll(database) > 0 else { return false }
            try AuditLog.record(.email(.turnedOff), by: deviceID, at: date, in: database)
            return true
        }
    }

    static func changes(from old: EmailSettings?, to new: EmailSettings, passwordEntered: Bool) -> [EmailChange] {
        var changes: [EmailChange] = []
        if let old {
            if old != new { changes.append(.changed(old: old, new: new)) }
        } else {
            changes.append(.setUp(new))
        }
        if passwordEntered { changes.append(.passwordEntered) }
        return changes
    }
}
