import Foundation
import GRDB
import HiveKit

/// Alerts in Hive's store, and how far through the job log they've been worked out.
struct AlertStore: Sendable {
    static let reminderInterval: TimeInterval = 24 * 60 * 60

    enum Change: Equatable, Sendable {
        /// Opens the alert and owes its first email, unless its condition is already open.
        case open(AlertFacts)
        /// Ends the condition. `notice` is owed in its place when the condition's email was tried, so
        /// nobody hears it's over without having heard it started.
        case resolve(AlertCondition, notice: AlertFacts?)
    }

    struct Applied: Sendable {
        var opened: [AlertFacts] = []
        var ended: [AlertFacts] = []
    }

    let database: HiveDatabase

    func all() throws -> [AlertRecord] {
        try database.writer.read { try AlertRecord.fetchAll($0) }
    }

    func checkedThrough() throws -> Int64 {
        try database.writer.read { try Int64.fetchOne($0, sql: "SELECT alertsCheckedThrough FROM hive") ?? 0 }
    }

    /// All or none, together with moving past the job log entry they came from. Returns the alerts
    /// opened, notices included, and the conditions ended.
    @discardableResult
    func apply(_ changes: [Change], at date: Date, checkedThrough logEntryID: Int64? = nil) throws -> Applied {
        guard !changes.isEmpty || logEntryID != nil else { return Applied() }
        return try database.writer.write { database in
            var applied = Applied()
            for change in changes {
                switch change {
                case .open(let facts):
                    guard try !AlertRecord.exists(database, key: facts.key) else { continue }
                    try AlertRecord(facts: facts, openedAt: date).insert(database)
                    applied.opened.append(facts)
                case .resolve(let condition, let notice):
                    guard let record = try AlertRecord.fetchOne(database, key: condition.key) else { continue }
                    try record.delete(database)
                    applied.ended.append(record.facts)
                    if let notice, record.lastEmailAt != nil, try !AlertRecord.exists(database, key: notice.key) {
                        try AlertRecord(facts: notice, openedAt: date).insert(database)
                        applied.opened.append(notice)
                    }
                }
            }
            if let logEntryID {
                try database.execute(sql: "UPDATE hive SET alertsCheckedThrough = ?", arguments: [logEntryID])
            }
            return applied
        }
    }

    /// Owes a reminder for each condition that reminds daily and was last emailed a day or more ago.
    /// Returns how many.
    func oweReminders(at date: Date) throws -> Int {
        try database.writer.write { database in
            let due = try AlertRecord
                .filter(Column("emailOwed") == nil && Column("lastEmailAt") <= date.addingTimeInterval(-Self.reminderInterval))
                .fetchAll(database)
                .filter { $0.facts.condition?.remindsDaily == true }
            for var record in due {
                record.emailOwed = .reminder
                try record.update(database)
            }
            return due.count
        }
    }

    /// The oldest alert with an email owed.
    func nextOwed() throws -> AlertRecord? {
        try database.writer.read { database in
            try AlertRecord.filter(Column("emailOwed") != nil).order(Column("openedAt"), Column.rowID).fetchOne(database)
        }
    }

    /// Recorded before the email goes, so a condition that ends while it's being sent still gets its notice.
    func startEmail(for record: AlertRecord, at date: Date) throws {
        try database.writer.write { database in
            try database.execute(sql: "UPDATE alert SET lastEmailAt = ? WHERE key = ?", arguments: [date, record.key])
        }
    }

    /// Sent or not, it isn't owed any more: a notice is done with, and a condition waits for its reminder.
    /// A condition that ended and started again meanwhile keeps the email it owes now.
    func finishEmail(for record: AlertRecord) throws {
        try database.writer.write { database in
            if record.facts.condition == nil {
                try database.execute(sql: "DELETE FROM alert WHERE key = ?", arguments: [record.key])
            } else {
                try database.execute(
                    sql: "UPDATE alert SET emailOwed = NULL WHERE key = ? AND emailOwed = ? AND openedAt = ?",
                    arguments: [record.key, record.emailOwed?.rawValue, record.openedAt]
                )
            }
        }
    }
}
