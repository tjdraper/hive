import Foundation

/// What Hive backs up from one server, usually one site, and when.
public struct BackupJob: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let serverID: UUID
    public let name: String
    public let directories: [BackupDirectory]
    public let databases: [BackupDatabase]
    /// In the Hive Mac's local time, earliest first.
    public let times: [TimeOfDay]
    public let retention: RetentionTiers

    public init(
        id: UUID,
        serverID: UUID,
        name: String,
        directories: [BackupDirectory],
        databases: [BackupDatabase],
        times: [TimeOfDay],
        retention: RetentionTiers
    ) {
        self.id = id
        self.serverID = serverID
        self.name = name
        self.directories = directories
        self.databases = databases
        self.times = times
        self.retention = retention
    }

    /// The job as it would be sent back unchanged, keeping every password, to start an edit from.
    public var draft: BackupJobDraft {
        BackupJobDraft(
            name: name,
            directories: directories,
            databases: databases.map { BackupDatabaseDraft(id: $0.id, settings: $0.settings, password: nil) },
            times: times,
            retention: retention
        )
    }
}

/// A job as Beekeeper sends it, to add one or to change one whole.
public struct BackupJobDraft: Codable, Hashable, Sendable {
    public var name: String
    public var directories: [BackupDirectory]
    public var databases: [BackupDatabaseDraft]
    public var times: [TimeOfDay]
    public var retention: RetentionTiers

    public init(
        name: String,
        directories: [BackupDirectory],
        databases: [BackupDatabaseDraft],
        times: [TimeOfDay],
        retention: RetentionTiers
    ) {
        self.name = name
        self.directories = directories
        self.databases = databases
        self.times = times
        self.retention = retention
    }
}

public struct BackupDirectory: Codable, Hashable, Sendable {
    /// An absolute path on the server.
    public var path: String
    /// Where it goes within each snapshot: relative, and nested with `/`, such as `images/galleries`.
    public var folder: String

    public init(path: String, folder: String) {
        self.path = path
        self.folder = folder
    }
}

public struct TimeOfDay: Codable, Hashable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}

/// Which of a job's snapshots it keeps. Days are counted only when they have a snapshot, so a long
/// outage never ages out history.
public struct RetentionTiers: Codable, Hashable, Sendable {
    /// Its newest snapshot from each of the newest this many days that have one.
    public var dailySnapshots: Int
    /// Its newest snapshot from each of the last this many months.
    public var monthlySnapshots: Int

    public init(dailySnapshots: Int, monthlySnapshots: Int) {
        self.dailySnapshots = dailySnapshots
        self.monthlySnapshots = monthlySnapshots
    }
}
