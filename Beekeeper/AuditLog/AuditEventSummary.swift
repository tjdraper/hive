import Foundation
import HiveKit

extension AuditEvent {
    var summary: String {
        switch self {
        case .pairedOnHiveMac:
            "Paired as Beekeeper on the Hive's Mac"
        case .pairingWindowOpened:
            "Opened a pairing window for a new device"
        case .pairingWindowClosed:
            "Closed the pairing window before a device used it"
        case .pairedWithCode(_, let openedByName):
            "Paired with a code from “\(openedByName)”"
        case .addressOptionsChanged(_, let new) where new.isEmpty:
            "Removed every address for other devices"
        case .addressOptionsChanged(_, let new):
            "Changed the addresses for other devices to \(new.map(\.summary).formatted(.list(type: .and)))"
        case .deviceRevoked(_, let deviceName):
            "Revoked “\(deviceName)”"
        case .hiveRenamed(let old, let new):
            "Renamed the Hive from “\(old)” to “\(new)”"
        case .networkAccessChanged(let old, let new):
            "Changed where Hive listens from \(old.summary) to \(new.summary)"
        case .portChanged(let old, let new):
            "Changed the port from \(old) to \(new)"
        case .localNetworkAdvertisingChanged(let isOn):
            isOn ? "Turned on advertising on the local network" : "Turned off advertising on the local network"
        case .buildExpiryWarningsChanged(let isOn):
            isOn ? "Turned on build expiry warnings" : "Turned off build expiry warnings"
        case .server(_, let serverName, let change):
            change.summary(serverName: serverName)
        case .backupJob(_, let serverName, let jobName, let change):
            change.summary(job: "“\(jobName)” on “\(serverName)”")
        case .backupDriveChosen(nil, let new):
            "Chose “\(new.name)” as the backup drive"
        case .backupDriveChosen(.some(let old), let new):
            "Chose “\(new.name)” as the backup drive, replacing “\(old.name)”"
        case .backupRunStarted(_, let serverName, let jobName):
            "Started a run of “\(jobName)” on “\(serverName)”"
        case .backupRunCancelled(_, let serverName, let jobName):
            "Cancelled the run of “\(jobName)” on “\(serverName)”"
        case .snapshotsDeleted(let deletion):
            deletion.summary
        case .confirmationKeyRegistered:
            "Set up confirming changes"
        case .identityRegenerated:
            "Gave the Hive a new identity, unpairing every device"
        case .email(let change):
            change.summary
        case .recoveryKeySaved(replacedAnother: false):
            "Saved the Hive's recovery key"
        case .recoveryKeySaved(replacedAnother: true):
            "Saved a new recovery key. Recovery files written before still open with the old one"
        case .restoredFromRecoveryFile(let writtenAt, let serverCount, let jobCount):
            "Restored the Hive from its recovery file of \(writtenAt.formatted(date: .abbreviated, time: .shortened)), "
                + "with \(serverCount) servers and \(jobCount) jobs"
        case .retentionStarted:
            "Started retention and quotas again after a restore"
        }
    }
}

extension AddressOption {
    var summary: String {
        port.map { "\(host) port \($0)" } ?? host
    }
}

extension EmailChange {
    var summary: String {
        switch self {
        case .setUp(let settings):
            "Set up email through \(settings.host):\(settings.port) to \(settings.recipients.formatted(.list(type: .and)))"
        case .changed(let old, let new) where old.host != new.host:
            "Changed the mail server from \(old.host) to \(new.host), sending to \(new.recipients.formatted(.list(type: .and)))"
        case .changed(_, let new):
            "Changed email to send through \(new.host):\(new.port) to \(new.recipients.formatted(.list(type: .and)))"
        case .passwordEntered:
            "Entered the email password"
        case .turnedOff:
            "Turned email off"
        }
    }
}

extension SnapshotDeletion {
    var summary: String {
        switch self {
        case .snapshot(_, let serverName, let jobName, let date):
            "Deleted the snapshot of “\(jobName)” on “\(serverName)” from \(date.formatted(date: .abbreviated, time: .shortened))"
        case .job(_, let serverName, let jobName, let count):
            "Deleted \(SnapshotCount(count)) of “\(jobName)” on “\(serverName)”"
        case .server(_, let serverName, let count):
            "Deleted \(SnapshotCount(count)) of “\(serverName)”"
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
        case .hostKeyConfirmed(nil, let new):
            "Confirmed the host key of “\(serverName)”, \(new.fingerprint)"
        case .hostKeyConfirmed(.some(let old), let new):
            "Confirmed a new host key for “\(serverName)”, \(new.fingerprint), replacing \(old.fingerprint)"
        case .newSSHKey(nil, let new):
            "Made Hive's SSH key for “\(serverName)”, \(new)"
        case .newSSHKey(.some(let old), let new):
            "Made a new SSH key for “\(serverName)”, \(new), replacing \(old)"
        case .sshKeyRotated(let old, let new):
            "Rotated Hive's SSH key on “\(serverName)” to \(new), replacing \(old)"
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
