import Foundation
import GRDB
import HiveKit

/// Writes each alert's email from its facts and what the store says when it's sent, so a reminder
/// gives the latest. Emails name servers, jobs and folders, since you need them to act (§13), and
/// never a secret.
struct AlertMessageBuilder: Sendable {
    let database: HiveDatabase
    let drives: BackupDriveLocator
    let calendar: Calendar

    func message(for alert: AlertRecord) throws -> EmailMessage {
        let isReminder = alert.emailOwed == .reminder
        // Looked up before reading the store, which the lookup reads too.
        let drive = try mountedDrive()
        return try database.writer.read { database in
            let text = AlertText(database: database, calendar: calendar)
            switch alert.facts {
            case .backupFailing(let jobID):
                return try backupFailing(jobID: jobID, since: alert.openedAt, isReminder: isReminder, text: text)
            case .backingUpAgain(let jobID, let logEntryID):
                return try backingUpAgain(jobID: jobID, logEntryID: logEntryID, text: text)
            case .driveUnavailable(let problem):
                return try driveUnavailable(problem, since: alert.openedAt, isReminder: isReminder, text: text)
            case .jobOverdue(let jobID, let since):
                return try jobOverdue(jobID: jobID, since: since, isReminder: isReminder, text: text)
            case .snapshotShrank(let jobID, _, let parts):
                return try snapshotShrank(jobID: jobID, parts: parts, text: text)
            case .hostKeyChanged(let serverID, let confirmed, let offered):
                return try hostKeyChanged(serverID: serverID, confirmed: confirmed, offered: offered, isReminder: isReminder, text: text)
            case .overQuota(let serverID, let since):
                return try overQuota(serverID: serverID, since: since, text: text)
            case .driveFillingUp:
                return driveFillingUp(drive, text: text)
            case .quotasExceedDrive:
                return try quotasExceedDrive(drive, text: text)
            }
        }
    }

    private func backupFailing(jobID: UUID, since: Date, isReminder: Bool, text: AlertText) throws -> EmailMessage {
        let job = try text.job(jobID)
        let last = try JobLogRecord
            .filter(Column("jobID") == jobID && Column("finishedAt") != nil && Column("failure") != nil)
            .filter(JobLogRecord.kindColumn != RemovalLogRecord.kind)
            .order(Column("id").desc)
            .fetchOne(text.database)

        var lines: [String] = []
        if isReminder {
            lines.append("Backups of \(job) are still failing. They started failing on \(text.date(since)).")
        } else {
            lines.append("A backup of \(job) failed.")
        }
        if let last, let failure = last.failure {
            lines += ["", "Its last run failed on \(text.date(last.finishedAt ?? last.startedAt))\(Self.part(of: last.run)):"]
            lines.append(failure.emailReason)
        }
        lines += ["", try text.lastSnapshot(ofJob: jobID)]
        lines += [
            "",
            "Hive runs it again at its next time. You'll get a reminder each day it keeps failing, and an email once it succeeds again.",
            "The job log in Beekeeper has the details.",
        ]
        let subject = isReminder ? "Backups of \(job) are still failing" : "Backup failed: \(job)"
        return EmailMessage(subject: subject, body: lines.joined(separator: "\n"))
    }

    private func backingUpAgain(jobID: UUID, logEntryID: Int64, text: AlertText) throws -> EmailMessage {
        let job = try text.job(jobID)
        let finishedAt = try Date.fetchOne(text.database, sql: "SELECT finishedAt FROM jobLogEntry WHERE id = ?", arguments: [logEntryID])
        let when = finishedAt.map { " on \(text.date($0))" } ?? ""
        return EmailMessage(
            subject: "Backing up again: \(job)",
            body: "A backup of \(job) succeeded\(when), after failing before. It's backing up as usual again."
        )
    }

    private func driveUnavailable(_ problem: DriveProblem, since: Date, isReminder: Bool, text: AlertText) throws -> EmailMessage {
        let name = try BackupDriveStore.chosen(in: text.database).map { "“\($0.name)”" } ?? "The backup drive"
        let (subject, explanation) = switch problem {
        case .notChosen:
            ("No backup drive is chosen", "No backup drive has been chosen, so no backups can run. Choose one in Beekeeper.")
        case .missing:
            (
                "The backup drive is missing",
                "\(name) isn't connected to the Hive Mac, so no backups can run. Connect it, and backups start again at their next times."
            )
        case .notThisHives:
            (
                "The backup drive isn't this Hive's",
                "The drive connected as \(name) isn't marked as this Hive's, so Hive won't write to it and no backups can run."
            )
        case .noFullDiskAccess:
            (
                "Hive has lost Full Disk Access",
                """
                Hive can't write to \(name), because it doesn't have Full Disk Access, so no backups can run. Turn it on for \
                Hive in System Settings › Privacy & Security › Full Disk Access on the Hive Mac.
                """
            )
        }
        var lines = [explanation]
        if isReminder { lines += ["", "This started on \(text.date(since))."] }
        lines += ["", "You'll get a reminder each day until it's fixed."]
        return EmailMessage(subject: isReminder ? "Still: \(subject.lowercasedFirst)" : subject, body: lines.joined(separator: "\n"))
    }

    private func jobOverdue(jobID: UUID, since: Date, isReminder: Bool, text: AlertText) throws -> EmailMessage {
        let job = try text.job(jobID)
        let lines = [
            "\(job) has gone longer without a complete backup than its schedule allows. It was due by \(text.date(since)).",
            "",
            try text.lastSnapshot(ofJob: jobID),
            "",
            "Its runs haven't failed, so it may not have been running: the Hive Mac may have been asleep or off, or its runs cancelled.",
            "You'll get a reminder each day until it completes a backup.",
        ]
        return EmailMessage(
            subject: isReminder ? "Still overdue: \(job)" : "Backup overdue: \(job)",
            body: lines.joined(separator: "\n")
        )
    }

    private func snapshotShrank(jobID: UUID, parts: [ShrunkPart], text: AlertText) throws -> EmailMessage {
        let job = try text.job(jobID)
        var lines = ["The newest snapshot of \(job) is much smaller than the one before:", ""]
        for part in parts {
            let kind = part.kind == .directory ? "Folder" : "Database"
            lines.append("\(kind) “\(part.name)”: \(text.size(part.bytes)), down from \(text.size(part.previousBytes))")
        }
        lines += [
            "",
            "That can mean files were deleted on the server, or a database was emptied, without anything failing.",
            "Earlier snapshots still have what was there. Check the server before retention removes them.",
        ]
        return EmailMessage(subject: "Snapshot much smaller: \(job)", body: lines.joined(separator: "\n"))
    }

    private func hostKeyChanged(
        serverID: UUID,
        confirmed: HostKeyFingerprint?,
        offered: HostKeyFingerprint?,
        isReminder: Bool,
        text: AlertText
    ) throws -> EmailMessage {
        let server = try text.server(serverID)
        let lastBackup = try Date.fetchOne(
            text.database,
            sql: "SELECT MAX(completedAt) FROM snapshot WHERE serverID = ? AND state = ?",
            arguments: [serverID, SnapshotState.complete.rawValue]
        )
        let lines = [
            "\(server) answered with a host key other than the one you confirmed, so Hive didn't connect and its backups are failing.",
            "",
            "Confirmed key: \(Self.fingerprint(confirmed))",
            "Key it sent:   \(Self.fingerprint(offered))",
            "",
            "Last successful backup: \(lastBackup.map(text.date) ?? "none yet")",
            "",
            """
            If the server's key changed on purpose, such as after reinstalling it, check the new fingerprint on the server and confirm \
            it in Beekeeper.
            """,
            "If it didn't, something may be standing in for the server. Don't confirm the new key.",
            "",
            "You'll get a reminder each day until the new key is confirmed or the original one comes back.",
        ]
        return EmailMessage(
            subject: isReminder ? "Still refusing \(server)'s changed host key" : "Host key changed: \(server)",
            body: lines.joined(separator: "\n")
        )
    }

    private func overQuota(serverID: UUID, since: Date, text: AlertText) throws -> EmailMessage {
        let server = try text.server(serverID)
        let quota = try Int64.fetchOne(text.database, sql: "SELECT quotaBytes FROM server WHERE id = ?", arguments: [serverID])
        let lines = [
            "\(server) has been over its quota\(quota.map { " of \(text.size($0))" } ?? "") since \(text.date(since)).",
            "",
            """
            Hive has removed every daily snapshot it can. Only monthly snapshots and each job's newest are left, and Hive never \
            removes those to meet a quota.
            """,
            "Raise the server's quota, or lower its jobs' retention, in Beekeeper.",
        ]
        return EmailMessage(subject: "Over quota: \(server)", body: lines.joined(separator: "\n"))
    }

    private func driveFillingUp(_ volume: MountedVolume?, text: AlertText) -> EmailMessage {
        let space = volume.map { " It has \(text.size($0.availableBytes)) free of \(text.size($0.totalBytes))." } ?? ""
        return EmailMessage(
            subject: "The backup drive is filling up",
            body: """
            The backup drive is almost full.\(space)

            Once it's full, backups fail. Give servers quotas, lower retention, or move Hive to a bigger drive.
            """
        )
    }

    private func quotasExceedDrive(_ volume: MountedVolume?, text: AlertText) throws -> EmailMessage {
        let quotas = try Int64.fetchOne(text.database, sql: "SELECT IFNULL(SUM(quotaBytes), 0) FROM server") ?? 0
        let size = volume.map { " of \(text.size($0.totalBytes))" } ?? ""
        return EmailMessage(
            subject: "Quotas add up to more than the backup drive holds",
            body: """
            The servers' quotas add up to \(text.size(quotas)), more than the backup drive's size\(size).

            The drive can fill up before any server reaches its quota, and then backups fail. Lower the quotas, or move Hive to a \
            bigger drive.
            """
        )
    }

    private func mountedDrive() throws -> MountedVolume? {
        guard case .ready(let drive) = try drives.locate() else { return nil }
        return drives.volumes.mountedVolumes().first { $0.uuid == drive.identity.volumeUUID }
    }

    /// Where in the run it failed, when it was a directory or database.
    private static func part(of run: BackupRun) -> String {
        if let database = run.databases.last, database.failure != nil { return ", dumping the database “\(database.name)”" }
        if let directory = run.directories.last, directory.failure != nil { return ", copying the folder “\(directory.folder)”" }
        return ""
    }

    private static func fingerprint(_ key: HostKeyFingerprint?) -> String {
        key.map { "\($0.fingerprint) (\($0.keyType))" } ?? "unknown"
    }
}

/// Names, dates and sizes as an email gives them.
private struct AlertText {
    let database: Database
    let calendar: Calendar

    /// Such as “Site” on “Web server”, as last known for a job since removed.
    func job(_ jobID: UUID) throws -> String {
        guard let names = try JobNames.lastKnown(jobID: jobID, in: database) else { return "a removed job" }
        return "“\(names.job)” on “\(names.server)”"
    }

    func server(_ serverID: UUID) throws -> String {
        try JobNames.lastKnownServerName(serverID, in: database).map { "“\($0)”" } ?? "A removed server"
    }

    func lastSnapshot(ofJob jobID: UUID) throws -> String {
        let date = try Date.fetchOne(
            database,
            sql: "SELECT MAX(completedAt) FROM snapshot WHERE jobID = ? AND state = ?",
            arguments: [jobID, SnapshotState.complete.rawValue]
        )
        return "Last complete snapshot: \(date.map(self.date) ?? "none yet")"
    }

    /// In the Hive Mac's time zone, in English whatever its language, as the rest of the email is.
    func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE d MMMM yyyy 'at' HH:mm zzz"
        return formatter.string(from: date)
    }

    func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private extension String {
    var lowercasedFirst: String {
        prefix(1).lowercased() + dropFirst()
    }
}
