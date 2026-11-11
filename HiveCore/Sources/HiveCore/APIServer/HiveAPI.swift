import Foundation
import HiveKit

/// Everything the API's routes work with.
public struct HiveAPI: Sendable {
    let hiveID: UUID
    /// The identity key's, which pairing codes carry.
    let pin: PublicKeyPin
    let signIn: SignInWorkflow
    let settingsStore: HiveSettingsStore
    let settings: HiveSettingsWorkflow
    let servers: ServerWorkflow
    let jobs: BackupJobWorkflow
    /// The Hive Mac's addresses, read fresh each time.
    let addresses: @Sendable () -> [NetworkInterfaceAddress]
    /// The port and address options, each time either changes.
    let addressChanges = Broadcaster<HiveAddresses>()
    let pairingWindows = PairingWindowStore()
    /// Kept for as long as Hive runs, so failures count across requests.
    let pairingLimiter = FailedAttemptLimiter<ClientAddress>(policy: .pairing)
    let hostKeys: HostKeyWorkflow
    let connectionTest: ConnectionTestWorkflow
    let backupDrive: BackupDriveWorkflow
    let runs: BackupRunCoordinator
    let jobStatus: JobStatusReader
    let scheduler: BackupScheduler
    let confirmations: ConfirmationVerifier
    /// Sends what Hive writes on its own, such as alerts.
    let emailDelivery: EmailDelivery
    let alerts: AlertMonitor
    let identityKeys: HiveKeyStore
    let restart: HiveRestart
    let recoveryFiles: RecoveryFileWriter
    let restore: RestoreWorkflow
    let sshKeyRotation: SSHKeyRotationWorkflow
    /// How often an open live updates response gets a line when nothing else is happening.
    let liveUpdateHeartbeat: Duration
    /// Checked on every request, since it can be turned off while Hive runs.
    let fullDiskAccess: @Sendable () -> FullDiskAccess
    let macSleep: @Sendable () async -> MacSleep

    var sshKeys: ServerSSHKeyWorkflow {
        ServerSSHKeyWorkflow(
            store: ServerSSHKeyStore(database: servers.store.database),
            sealer: servers.sealer,
            settings: settingsStore,
            addresses: addresses,
            now: signIn.now
        )
    }

    var email: EmailSettingsWorkflow {
        EmailSettingsWorkflow(sender: emailDelivery.sender, now: signIn.now)
    }

    var serverSpace: ServerSpaceReader {
        ServerSpaceReader(database: servers.store.database)
    }

    var jobLog: JobLog {
        JobLog(database: servers.store.database)
    }

    var devices: DeviceStore {
        signIn.devices
    }

    var pairingWindow: PairingWindowWorkflow {
        PairingWindowWorkflow(
            hiveID: hiveID,
            pin: pin,
            settings: settingsStore,
            database: servers.store.database,
            windows: pairingWindows,
            isRestarting: { [restart] in restart.isRequested },
            now: signIn.now
        )
    }

    var codePairing: CodePairingWorkflow {
        CodePairingWorkflow(
            settings: settingsStore,
            devices: signIn.devices,
            windows: pairingWindows,
            limiter: pairingLimiter,
            apiVersions: signIn.apiVersions,
            hiveID: hiveID,
            isRestarting: { [restart] in restart.isRequested },
            now: signIn.now
        )
    }

    var revocation: DeviceRevocationWorkflow {
        DeviceRevocationWorkflow(devices: signIn.devices, sessions: signIn.sessions, now: signIn.now)
    }

    var auditLog: AuditLog {
        AuditLog(database: servers.store.database)
    }

    var identity: IdentityRegenerationWorkflow {
        IdentityRegenerationWorkflow(
            keys: identityKeys,
            database: servers.store.database,
            sessions: signIn.sessions,
            restart: restart,
            now: signIn.now
        )
    }

    /// True once Hive is restarting, such as for a new identity.
    public var isRestarting: Bool {
        restart.isRequested
    }

    var recoveryKey: RecoveryKeyWorkflow {
        RecoveryKeyWorkflow(store: RecoveryKeyStore(database: servers.store.database), files: recoveryFiles, now: signIn.now)
    }

    var restoreState: RestoreStateReader {
        RestoreStateReader(database: servers.store.database)
    }

    var retentionPause: RetentionPauseStore {
        RetentionPauseStore(database: servers.store.database)
    }

    var removalEstimator: RemovalEstimator {
        RemovalEstimator(database: servers.store.database, calendar: jobs.schedule.calendar)
    }

    var removedJobs: RemovedJobReader {
        RemovedJobReader(database: servers.store.database)
    }

    var snapshotDeletions: SnapshotDeletionStore {
        SnapshotDeletionStore(database: servers.store.database)
    }

    var snapshots: JobSnapshotReader {
        JobSnapshotReader(
            database: servers.store.database,
            drives: BackupDriveLocator(store: backupDrive.store, volumes: backupDrive.volumes, hiveID: hiveID)
        )
    }

    /// `identityKeys` is where the identity key is saved, for regenerating it. The recovery file is
    /// written in `dataDirectory`.
    public init(
        hiveID: UUID,
        pin: PublicKeyPin,
        database: HiveDatabase,
        dataDirectory: URL,
        settings: HiveSettingsStore,
        listeners: ListenerCoordinator,
        sealer: SecretSealer,
        identityKeys: HiveKeyStore,
        rsync: URL
    ) {
        let devices = DeviceStore(database: database)
        self.init(
            hiveID: hiveID,
            pin: pin,
            database: database,
            dataDirectory: dataDirectory,
            signIn: SignInWorkflow(hiveID: hiveID, devices: devices, sessions: SessionStore()),
            settingsStore: settings,
            listeners: listeners,
            sealer: sealer,
            identityKeys: identityKeys,
            restart: HiveRestart(delay: .seconds(1)),
            smtp: NIOSMTPConnector(),
            fullDiskAccess: { FullDiskAccessProbe().check() },
            ssh: SSHRunner(),
            hostKeyScanner: HostKeyScanner(),
            addresses: { NetworkInterfaceList.current() },
            hostNaming: SystemHostNaming(),
            volumes: MountedVolumeList(),
            rsync: RsyncRunner(rsync: rsync),
            dumps: DatabaseDumpRunner(),
            origin: { .server($0) },
            calendar: .autoupdatingCurrent,
            sleepPrevention: PowerAssertion(),
            macSleep: { await SleepSettingReader().read() },
            startupDriveGrace: 5 * 60,
            pause: { try await Task.sleep(for: $0) },
            liveUpdateHeartbeat: .seconds(15),
            now: Date.init
        )
    }

    init(
        hiveID: UUID,
        pin: PublicKeyPin,
        database: HiveDatabase,
        dataDirectory: URL,
        signIn: SignInWorkflow,
        settingsStore: HiveSettingsStore,
        listeners: any ListenerControl,
        sealer: SecretSealer,
        identityKeys: HiveKeyStore,
        restart: HiveRestart,
        smtp: any SMTPConnecting,
        fullDiskAccess: @escaping @Sendable () -> FullDiskAccess,
        ssh: any SSHRunning,
        hostKeyScanner: any HostKeyScanning,
        addresses: @escaping @Sendable () -> [NetworkInterfaceAddress],
        hostNaming: any HostNaming,
        volumes: any VolumeListing,
        rsync: RsyncRunner,
        dumps: DatabaseDumpRunner,
        origin: @escaping @Sendable (SSHTarget) -> BackupOrigin,
        calendar: Calendar,
        sleepPrevention: any SleepPreventing,
        macSleep: @escaping @Sendable () async -> MacSleep,
        startupDriveGrace: TimeInterval,
        pause: @escaping @Sendable (Duration) async throws -> Void,
        liveUpdateHeartbeat: Duration,
        now: @escaping @Sendable () -> Date
    ) {
        self.hiveID = hiveID
        self.pin = pin
        self.signIn = signIn
        self.settingsStore = settingsStore
        settings = HiveSettingsWorkflow(
            store: settingsStore, listeners: listeners, interfaces: addresses,
            suggestions: SuggestedHostResolver(naming: hostNaming), addressChanges: addressChanges, now: now
        )
        let servers = ServerStore(database: database)
        self.servers = ServerWorkflow(store: servers, sealer: sealer, now: now)
        let schedule = ScheduleCalendar(calendar: calendar)
        jobs = BackupJobWorkflow(store: BackupJobStore(database: database), sealer: sealer, schedule: schedule, now: now)
        self.addresses = addresses
        hostKeys = HostKeyWorkflow(
            store: HostKeyStore(database: database), servers: servers, scanner: hostKeyScanner, pending: PendingHostKeyScans(), now: now
        )
        connectionTest = ConnectionTestWorkflow(targets: SSHTargetLoader(database: database, sealer: sealer), ssh: ssh)
        let drives = BackupDriveLocator(store: BackupDriveStore(database: database), volumes: volumes, hiveID: hiveID)
        backupDrive = BackupDriveWorkflow(store: drives.store, volumes: volumes, hiveID: hiveID, now: now)
        runs = BackupRunCoordinator(
            workflow: BackupRunWorkflow(
                hiveID: hiveID, database: database, drives: drives, targets: connectionTest.targets, rsync: rsync, dumps: dumps,
                passwords: DatabasePasswordLoader(database: database, sealer: sealer), origin: origin, now: now
            ),
            retention: RetentionWorkflow(database: database, drives: drives, calendar: calendar, now: now),
            sleep: sleepPrevention,
            startupDriveGrace: startupDriveGrace,
            pause: pause
        )
        jobStatus = JobStatusReader(database: database, runs: runs, schedule: schedule, now: now)
        self.liveUpdateHeartbeat = liveUpdateHeartbeat
        scheduler = BackupScheduler(database: database, schedule: schedule, runs: runs, now: now)
        self.fullDiskAccess = fullDiskAccess
        self.macSleep = macSleep
        confirmations = ConfirmationVerifier(hiveID: hiveID, database: database, now: now)
        let mail = EmailSender(database: database, settings: settingsStore, sealer: sealer, connector: smtp, calendar: calendar, now: now)
        emailDelivery = EmailDelivery(sender: mail, pause: pause, now: now)
        alerts = AlertMonitor(
            database: database, drives: drives, statuses: jobStatus, scanner: hostKeyScanner,
            fullDiskAccess: fullDiskAccess, delivery: emailDelivery, calendar: calendar, now: now
        )
        self.identityKeys = identityKeys
        self.restart = restart
        recoveryFiles = RecoveryFileWriter(database: database, sealer: sealer, directory: dataDirectory, now: now)
        restore = RestoreWorkflow(database: database, settings: settingsStore, sealer: sealer, volumes: volumes, restart: restart, now: now)
        sshKeyRotation = SSHKeyRotationWorkflow(database: database, sealer: sealer, ssh: ssh, runs: runs, settings: settingsStore, now: now)
    }
}
