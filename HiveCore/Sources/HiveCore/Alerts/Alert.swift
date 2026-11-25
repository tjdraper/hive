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
    /// The device's name is kept, since it may be revoked before the email goes.
    case buildExpiring(deviceID: UUID, deviceName: String, build: BeekeeperBuild, warning: BuildExpiryWarning)
    /// Servers' figures (§8).
    case stoppedReporting(StoppedServer)
    /// Servers that stopped at the same time, which usually means Hive's own connection, so they're
    /// one email.
    case stoppedTogether([StoppedServer])
    case clockAhead(serverID: UUID, offsetSeconds: Int64?)
    case filesystemFilling(serverID: UUID, mountPoint: String, reading: FilesystemReading)
    case memoryShort(serverID: UUID, reading: MemoryReading)
    case cpuBusy(serverID: UUID, reading: CPUReading)
    /// Notices. `since` is when the first of them reported again.
    case reportingAgain(serverIDs: [UUID], since: Date)
    /// `bootedAt` is on the server's clock.
    case serverRestarted(serverID: UUID, bootedAt: Int64)

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
        case .stoppedReporting(let server): .stoppedReporting(serverID: server.serverID)
        case .stoppedTogether(let servers): .stoppedTogether(serverIDs: servers.map(\.serverID))
        case .clockAhead(let serverID, _): .clockAhead(serverID: serverID)
        case .filesystemFilling(let serverID, let mountPoint, _): .filesystemFilling(serverID: serverID, mountPoint: mountPoint)
        case .memoryShort(let serverID, _): .memoryShort(serverID: serverID)
        case .cpuBusy(let serverID, _): .cpuBusy(serverID: serverID)
        case .backingUpAgain, .snapshotShrank, .buildExpiring, .reportingAgain, .serverRestarted: nil
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
        case .buildExpiring(_, _, let build, let warning): "buildExpiring(\(build.distribution.rawValue), \(warning.rawValue))"
        case .stoppedReporting: "stoppedReporting"
        case .stoppedTogether(let servers): "stoppedTogether(\(servers.count))"
        case .clockAhead: "clockAhead"
        case .filesystemFilling: "filesystemFilling"
        case .memoryShort: "memoryShort"
        case .cpuBusy: "cpuBusy"
        case .reportingAgain(let serverIDs, _): "reportingAgain(\(serverIDs.count))"
        case .serverRestarted: "serverRestarted"
        }
    }

    /// Unique among alerts. A notice's names the run or build it's about, so working through that run
    /// again can't send it twice.
    var key: String {
        switch self {
        case .backingUpAgain(_, let logEntryID): "backingUpAgain:\(logEntryID)"
        case .snapshotShrank(_, let logEntryID, _): "snapshotShrank:\(logEntryID)"
        case .buildExpiring(let deviceID, _, let build, let warning):
            "buildExpiring:\(deviceID.uuidString):\(build.version):\(build.build):\(warning.rawValue)"
        case .reportingAgain(let serverIDs, let date):
            "reportingAgain:\(AlertCondition.listKey(serverIDs)):\(Int64(date.timeIntervalSince1970))"
        case .serverRestarted(let serverID, let bootedAt): "serverRestarted:\(serverID.uuidString):\(bootedAt)"
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
    case stoppedReporting(serverID: UUID)
    case stoppedTogether(serverIDs: [UUID])
    case clockAhead(serverID: UUID)
    case filesystemFilling(serverID: UUID, mountPoint: String)
    case memoryShort(serverID: UUID)
    case cpuBusy(serverID: UUID)

    var key: String {
        switch self {
        case .backupFailing(let jobID): "backupFailing:\(jobID.uuidString)"
        case .driveUnavailable: "driveUnavailable"
        case .jobOverdue(let jobID): "jobOverdue:\(jobID.uuidString)"
        case .hostKeyChanged(let serverID): "hostKeyChanged:\(serverID.uuidString)"
        case .overQuota(let serverID): "overQuota:\(serverID.uuidString)"
        case .driveFillingUp: "driveFillingUp"
        case .quotasExceedDrive: "quotasExceedDrive"
        case .stoppedReporting(let serverID): "stoppedReporting:\(serverID.uuidString)"
        case .stoppedTogether(let serverIDs): "stoppedTogether:\(Self.listKey(serverIDs))"
        case .clockAhead(let serverID): "clockAhead:\(serverID.uuidString)"
        case .filesystemFilling(let serverID, let mountPoint): "filesystemFilling:\(serverID.uuidString):\(mountPoint)"
        case .memoryShort(let serverID): "memoryShort:\(serverID.uuidString)"
        case .cpuBusy(let serverID): "cpuBusy:\(serverID.uuidString)"
        }
    }

    /// The same whatever order the servers are in.
    static func listKey(_ serverIDs: [UUID]) -> String {
        serverIDs.map(\.uuidString).sorted().joined(separator: ",")
    }

    /// Emailed again each day while it lasts. Space warnings aren't: backups still run meanwhile, and
    /// fixing them can wait for a quota or retention change. Nor are figures that come and go, such as
    /// CPU, which stay open until they've cleared for an hour.
    var remindsDaily: Bool {
        switch self {
        case .backupFailing, .driveUnavailable, .jobOverdue, .hostKeyChanged: true
        case .stoppedReporting, .stoppedTogether, .clockAhead, .filesystemFilling: true
        case .overQuota, .driveFillingUp, .quotasExceedDrive, .memoryShort, .cpuBusy: false
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
