import Foundation
import GRDB
import HiveKit

/// Why Hive can't use the backup drive.
enum DriveProblem: String, Codable, Sendable {
    case notChosen
    case missing
    case notThisHives
    case noFullDiskAccess
}

/// A directory or database in a snapshot much smaller than in the one before.
struct ShrunkPart: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case directory
        case database
    }

    let kind: Kind
    /// The directory's folder within the snapshot, or the database's name.
    let name: String
    let previousBytes: Int64
    let bytes: Int64
}

/// Something going on that's emailed about (§13), and what the email needs that can't be read again
/// when it's sent.
enum AlertFacts: Codable, Equatable, Sendable {
    case backupFailing(jobID: UUID)
    case driveUnavailable(DriveProblem)
    case jobOverdue(jobID: UUID, since: Date)
    case hostKeyChanged(serverID: UUID, confirmed: HostKeyFingerprint?, offered: HostKeyFingerprint?)
    case overQuota(serverID: UUID, since: Date)
    case driveFillingUp
    case quotasExceedDrive
    /// Notices, sent once.
    case backingUpAgain(jobID: UUID, logEntryID: Int64)
    case snapshotShrank(jobID: UUID, logEntryID: Int64, parts: [ShrunkPart])

    /// Nil for a notice.
    var condition: AlertCondition? {
        switch self {
        case .backupFailing(let jobID): .backupFailing(jobID: jobID)
        case .driveUnavailable: .driveUnavailable
        case .jobOverdue(let jobID, _): .jobOverdue(jobID: jobID)
        case .hostKeyChanged(let serverID, _, _): .hostKeyChanged(serverID: serverID)
        case .overQuota(let serverID, _): .overQuota(serverID: serverID)
        case .driveFillingUp: .driveFillingUp
        case .quotasExceedDrive: .quotasExceedDrive
        case .backingUpAgain, .snapshotShrank: nil
        }
    }

    /// For the system log, which never names a server or job.
    var kind: String {
        switch self {
        case .backupFailing: "backupFailing"
        case .driveUnavailable(let problem): "driveUnavailable(\(problem.rawValue))"
        case .jobOverdue: "jobOverdue"
        case .hostKeyChanged: "hostKeyChanged"
        case .overQuota: "overQuota"
        case .driveFillingUp: "driveFillingUp"
        case .quotasExceedDrive: "quotasExceedDrive"
        case .backingUpAgain: "backingUpAgain"
        case .snapshotShrank: "snapshotShrank"
        }
    }

    /// Unique among alerts. A notice's names the run it's about, so working through that run again
    /// can't send it twice.
    var key: String {
        switch self {
        case .backingUpAgain(_, let logEntryID): "backingUpAgain:\(logEntryID)"
        case .snapshotShrank(_, let logEntryID, _): "snapshotShrank:\(logEntryID)"
        default: condition?.key ?? ""
        }
    }
}

/// Something that lasts, so it's emailed about once when it starts, however many runs it affects.
enum AlertCondition: Hashable, Sendable {
    case backupFailing(jobID: UUID)
    case driveUnavailable
    case jobOverdue(jobID: UUID)
    case hostKeyChanged(serverID: UUID)
    case overQuota(serverID: UUID)
    case driveFillingUp
    case quotasExceedDrive

    var key: String {
        switch self {
        case .backupFailing(let jobID): "backupFailing:\(jobID.uuidString)"
        case .driveUnavailable: "driveUnavailable"
        case .jobOverdue(let jobID): "jobOverdue:\(jobID.uuidString)"
        case .hostKeyChanged(let serverID): "hostKeyChanged:\(serverID.uuidString)"
        case .overQuota(let serverID): "overQuota:\(serverID.uuidString)"
        case .driveFillingUp: "driveFillingUp"
        case .quotasExceedDrive: "quotasExceedDrive"
        }
    }

    /// Emailed again each day while it lasts. Space warnings aren't: backups still run meanwhile, and
    /// fixing them can wait for a quota or retention change.
    var remindsDaily: Bool {
        switch self {
        case .backupFailing, .driveUnavailable, .jobOverdue, .hostKeyChanged: true
        case .overQuota, .driveFillingUp, .quotasExceedDrive: false
        }
    }
}

/// An alert in Hive's store: a condition while it lasts, or a notice until it's been sent. It says
/// which email is owed, so a restart neither forgets one nor sends one twice.
struct AlertRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "alert"

    enum Email: String, Codable, Sendable {
        case first
        case reminder
    }

    let key: String
    /// Kept as JSON, which GRDB does for a property that isn't a database value.
    let facts: AlertFacts
    let openedAt: Date
    var emailOwed: Email?
    var lastEmailAt: Date?

    init(facts: AlertFacts, openedAt: Date) {
        key = facts.key
        self.facts = facts
        self.openedAt = openedAt
        emailOwed = .first
        lastEmailAt = nil
    }
}
