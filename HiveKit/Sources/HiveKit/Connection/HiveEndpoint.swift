import Foundation

public enum HiveEndpoint {
    public static let health = "/health"
    public static let signInChallenge = "/sign-in/challenge"
    public static let signIn = "/sign-in"
    public static let overview = "/hive"
    public static let devices = "/devices"
    public static let settings = "/settings"
    /// Newest first. `?before=<entry ID>` gives the page after one already shown.
    public static let auditLog = "/audit-log"
    /// `POST` opens a pairing window, answering with its `PairingWindow`. Confirmed. `GET` reads its
    /// `PairingWindowState`, and `DELETE` closes it.
    public static let pairingWindow = "/pairing-window"
    /// `POST` a `PairingRequest` to pair a new device through the open window. Answers 404 for every
    /// request without a good token, as if it weren't there.
    public static let pairing = "/pairing"

    public static let servers = "/servers"
    /// Every server's jobs. A job is added under its server, with `jobs(onServer:)`.
    public static let jobs = "/jobs"
    /// `GET` reads the chosen drive and the volumes mounted, and `PUT` chooses one.
    public static let backupDrive = "/backup-drive"
    /// Every job's `JobStatus`.
    public static let jobStatus = "/job-status"
    /// Newest first. `?before=<entry ID>` gives the page after one already shown, `?job=<ID>` or
    /// `?server=<ID>` keeps only that job's or server's entries, and `?problems=true` keeps only runs
    /// that failed and removals that left a snapshot behind.
    public static let jobLog = "/job-log"
    /// A response that stays open, one `LiveUpdate` per line, until the session ends.
    public static let liveUpdates = "/live-updates"
    /// `POST` gives a `ConfirmationChallenge` for one confirmed request.
    public static let confirmationChallenge = "/confirmation/challenge"
    /// `PUT` registers the signed-in device's `ConfirmationKeyRegistration`.
    public static let confirmationKey = "/confirmation/key"
    /// `POST` makes Hive a new identity key, unpairs every device and restarts Hive. Confirmed.
    public static let identityRegeneration = "/identity/regenerate"
    /// `GET` reads the `EmailSettingsState`, `PUT` an `EmailSettingsChange` sets it up or changes it, and
    /// `DELETE` turns email off. Changing the host is confirmed.
    public static let email = "/email"
    /// `POST` sends a test email to every recipient, once, and answers with its `TestEmailOutcome`.
    public static let testEmail = "/email/test"
    /// `GET` reads the `RecoveryKeyState`, and `PUT` a `RecoveryKeyChange` gives the Hive a recovery key
    /// or replaces its old one. Confirmed.
    public static let recoveryKey = "/recovery-key"
    /// `GET` reads the latest `RecoveryFileDownload`, answering 404 while there isn't one.
    public static let recoveryFile = "/recovery-file"
    /// `GET` reads the `RestoreState`, and `POST` a `RestoreRequest` restores the Hive from a recovery
    /// file, answering with a `RestoreOutcome`, then restarts it. Only from the Hive's own Mac.
    public static let restore = "/restore"
    /// `DELETE` starts retention and quotas again after a restore. Confirmed.
    public static let retentionPause = "/retention-pause"
    /// `GET` reads the `SSHKeyRotationState`, and `POST` starts giving every server a new SSH key,
    /// answering 409 while a rotation runs. Confirmed.
    public static let sshKeyRotation = "/ssh-keys/rotation"
    /// A snapshot is deleted with `snapshot(_:)`.
    public static let snapshots = "/snapshots"
    /// `GET` lists the `RemovedJob`s whose snapshots stayed on the chosen backup drive.
    public static let removedJobs = "/removed-jobs"
    /// `GET` reads a `ServerMetricsSummary` for every server with metrics, for the dashboard.
    public static let metricsSummary = "/metrics"

    public static func device(_ id: UUID) -> String {
        "\(devices)/\(id.uuidString)"
    }

    public static func server(_ id: UUID) -> String {
        "\(servers)/\(id.uuidString)"
    }

    /// `GET` reads Hive's SSH key for the server, and `POST` makes a new one.
    public static func sshKey(onServer id: UUID) -> String {
        "\(server(id))/ssh-key"
    }

    /// `POST` scans the server's host key without recording it.
    public static func hostKeyScan(onServer id: UUID) -> String {
        "\(hostKey(onServer: id))/scan"
    }

    /// `PUT` records the key the last scan found.
    public static func hostKey(onServer id: UUID) -> String {
        "\(server(id))/host-key"
    }

    /// `POST` connects with Hive's key and runs a command that changes nothing.
    public static func connectionTest(onServer id: UUID) -> String {
        "\(server(id))/connection-test"
    }

    /// `GET` reads the server's `ServerSpace`.
    public static func space(ofServer id: UUID) -> String {
        "\(server(id))/space"
    }

    public static func jobs(onServer id: UUID) -> String {
        "\(server(id))\(jobs)"
    }

    public static func job(_ id: UUID) -> String {
        "\(jobs)/\(id.uuidString)"
    }

    /// `POST` queues a run, answering 409 while the job is already waiting or running. `DELETE` cancels its
    /// waiting or running run. `GET` reads its `JobStatus`.
    public static func run(ofJob id: UUID) -> String {
        "\(job(id))/run"
    }

    /// `GET` reads the job's `JobSnapshots`, for a removed job's too. `DELETE` deletes them all. Confirmed.
    public static func snapshots(ofJob id: UUID) -> String {
        "\(job(id))/snapshots"
    }

    /// `DELETE` deletes every snapshot of the server's, its removed jobs' included. Confirmed.
    public static func snapshots(ofServer id: UUID) -> String {
        "\(server(id))/snapshots"
    }

    /// `DELETE` deletes one snapshot. Confirmed.
    public static func snapshot(_ id: UUID) -> String {
        "\(snapshots)/\(id.uuidString)"
    }

    /// `POST` opens a window for the server's Scout to enroll through, answering with its
    /// `EnrollmentWindow`. Confirmed. `DELETE` closes it.
    public static func enrollmentWindow(forServer id: UUID) -> String {
        "\(server(id))/enrollment-window"
    }

    /// `GET` reads the server's `ServerMetricsState`. `DELETE` removes its metrics: its Scout can't sign
    /// in again and its sessions end, while the figures already kept age out.
    public static func metrics(ofServer id: UUID) -> String {
        "\(server(id))/metrics"
    }

    /// `GET` reads the `MetricsSeries` of `figures` from `from` up to `to`, seconds since 1970 on the
    /// server's clock, at most `longestMetricsRange` apart.
    public static func metricsSeries(ofServer id: UUID, from start: Int64, to end: Int64, figures: [MetricsFigure]) -> String {
        "\(metrics(ofServer: id))/series?from=\(start)&to=\(end)&figures=\(figures.map(\.rawValue).joined(separator: ","))"
    }

    public static let longestMetricsRange: Int64 = 400 * 86_400

    /// `GET` reads the server's `ProcessMoment` at `at`, seconds since 1970 on the server's clock.
    public static func processes(ofServer id: UUID, at moment: Int64) -> String {
        "\(metrics(ofServer: id))/processes?at=\(moment)"
    }

    /// `GET` reads a `FilesystemForecast` for each of the server's filesystems.
    public static func filesystemForecasts(ofServer id: UUID) -> String {
        "\(metrics(ofServer: id))/filesystem-forecasts"
    }

    /// `GET` reads the `BackupRunMark`s of the server's runs from `from` up to `to`, seconds since 1970
    /// on the server's clock.
    public static func backupRunMarks(ofServer id: UUID, from start: Int64, to end: Int64) -> String {
        "\(metrics(ofServer: id))/backup-runs?from=\(start)&to=\(end)"
    }

    /// `POST` finds out over SSH, changing nothing, what Hive can do about Scout on the server, answering
    /// with its `ScoutCheckResult`.
    public static func scoutCheck(onServer id: UUID) -> String {
        "\(server(id))/scout-check"
    }

    /// `POST` a `ScoutActionRequest` to act on the server's Scout over SSH, answering with its
    /// `ScoutActionResult`. Installing and enrolling again are confirmed.
    public static func scoutAction(onServer id: UUID) -> String {
        "\(server(id))/scout-action"
    }

    /// `POST` a `QuotaEstimateRequest` for the `RemovalEstimate` of changing the server's quota.
    public static func quotaEstimate(ofServer id: UUID) -> String {
        "\(server(id))/quota-estimate"
    }

    /// `POST` `RetentionTiers` for the `RemovalEstimate` of changing the job's tiers.
    public static func retentionEstimate(ofJob id: UUID) -> String {
        "\(job(id))/retention-estimate"
    }
}
