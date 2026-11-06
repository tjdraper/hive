import Foundation
import HiveKit

extension AuditEvent {
    var summary: String {
        switch self {
        case .pairedOnHiveMac:
            "Paired as Beekeeper on the Hive's Mac"
        case .deviceRevoked(_, let deviceName):
            "Revoked “\(deviceName)”"
        case .hiveRenamed(let old, let new):
            "Renamed the Hive from “\(old)” to “\(new)”"
        case .networkAccessChanged(let old, let new):
            "Changed where Hive listens from \(old.summary) to \(new.summary)"
        case .portChanged(let old, let new):
            "Changed the port from \(old) to \(new)"
        case .server(_, let serverName, let change):
            change.summary(serverName: serverName)
        case .backupJob(_, let serverName, let jobName, let change):
            change.summary(job: "“\(jobName)” on “\(serverName)”")
        }
    }
}

extension ServerChange {
    func summary(serverName: String) -> String {
        switch self {
        case .added(let connection):
            "Added the server “\(serverName)” at \(connection.summary)"
        case .renamed(let old, let new):
            "Renamed the server “\(old)” to “\(new)”"
        case .connection(let old, let new):
            "Changed “\(serverName)” from \(old.summary) to \(new.summary), clearing its database passwords and host key"
        case .quota(let old, let new):
            "Changed the quota of “\(serverName)” from \(Self.quota(old)) to \(Self.quota(new))"
        case .removed:
            "Removed the server “\(serverName)” and its jobs, keeping their snapshots"
        }
    }

    private static func quota(_ bytes: Int64?) -> String {
        bytes.map { $0.formatted(.byteCount(style: .file)) } ?? "no limit"
    }
}

extension BackupJobChange {
    /// `job` names the job and its server.
    func summary(job: String) -> String {
        switch self {
        case .added:
            "Added the job \(job)"
        case .renamed(let old, _):
            "Renamed the job “\(old)”, now \(job)"
        case .directories(_, let new):
            "Changed the directories of \(job) to \(new.map(\.folder).formatted())"
        case .databases(_, let new):
            "Changed the databases of \(job) to \(new.map(\.name).formatted())"
        case .databasePassword(let databaseName):
            "Entered the password for “\(databaseName)” in \(job)"
        case .times(_, let new):
            "Changed when \(job) runs to \(new.map(\.summary).formatted())"
        case .retention(let old, let new):
            "Changed what \(job) keeps from \(old.summary) to \(new.summary)"
        case .removed:
            "Removed the job \(job), keeping its snapshots"
        }
    }
}

extension ServerConnection {
    var summary: String {
        "\(user)@\(host):\(port)"
    }
}

extension TimeOfDay {
    var summary: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        guard let date = Calendar.current.date(from: components) else { return "\(hour):\(minute)" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

extension RetentionTiers {
    var summary: String {
        "\(dailySnapshots) daily and \(monthlySnapshots) monthly snapshots"
    }
}
