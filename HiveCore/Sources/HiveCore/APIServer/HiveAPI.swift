import Foundation
import HiveKit

/// Everything the API's routes work with.
public struct HiveAPI: Sendable {
    let hiveID: UUID
    let signIn: SignInWorkflow
    let devices: DeviceStore
    let revocation: DeviceRevocationWorkflow
    let settingsStore: HiveSettingsStore
    let settings: HiveSettingsWorkflow
    let auditLog: AuditLog
    let servers: ServerWorkflow
    let jobs: BackupJobWorkflow
    let sshKeys: ServerSSHKeyWorkflow
    let hostKeys: HostKeyWorkflow
    let connectionTest: ConnectionTestWorkflow
    let backupDrive: BackupDriveWorkflow
    let runs: BackupRunCoordinator
    let jobStatus: JobStatusReader
    let jobLog: JobLog
    let scheduler: BackupScheduler
    /// Checked on every request, since it can be turned off while Hive runs.
    let fullDiskAccess: @Sendable () -> FullDiskAccess
    let macSleep: @Sendable () async -> MacSleep

    var serverSpace: ServerSpaceReader {
        ServerSpaceReader(database: servers.store.database)
    }

    public init(
        hiveID: UUID,
        database: HiveDatabase,
        settings: HiveSettingsStore,
        listeners: ListenerCoordinator,
        sealer: SecretSealer,
        rsync: URL
    ) {
        let devices = DeviceStore(database: database)
        self.init(
            hiveID: hiveID,
            database: database,
            signIn: SignInWorkflow(hiveID: hiveID, devices: devices, sessions: SessionStore()),
            settingsStore: settings,
            listeners: listeners,
            sealer: sealer,
            fullDiskAccess: { FullDiskAccessProbe().check() },
            ssh: SSHRunner(),
            hostKeyScanner: HostKeyScanner(),
            addresses: { NetworkInterfaceList.current() },
            volumes: MountedVolumeList(),
            rsync: RsyncRunner(rsync: rsync),
            dumps: DatabaseDumpRunner(),
            origin: { .server($0) },
            calendar: .autoupdatingCurrent,
            sleepPrevention: PowerAssertion(),
            macSleep: { await SleepSettingReader().read() },
            startupDriveGrace: 5 * 60,
            pause: { try await Task.sleep(for: $0) },
            now: Date.init
        )
    }

    init(
        hiveID: UUID,
        database: HiveDatabase,
        signIn: SignInWorkflow,
        settingsStore: HiveSettingsStore,
        listeners: any ListenerControl,
        sealer: SecretSealer,
        fullDiskAccess: @escaping @Sendable () -> FullDiskAccess,
        ssh: any SSHRunning,
        hostKeyScanner: any HostKeyScanning,
        addresses: @escaping @Sendable () -> [NetworkInterfaceAddress],
        volumes: any VolumeListing,
        rsync: RsyncRunner,
        dumps: DatabaseDumpRunner,
        origin: @escaping @Sendable (SSHTarget) -> BackupOrigin,
        calendar: Calendar,
        sleepPrevention: any SleepPreventing,
        macSleep: @escaping @Sendable () async -> MacSleep,
        startupDriveGrace: TimeInterval,
        pause: @escaping @Sendable (Duration) async throws -> Void,
        now: @escaping @Sendable () -> Date
    ) {
        self.hiveID = hiveID
        self.signIn = signIn
        devices = signIn.devices
        revocation = DeviceRevocationWorkflow(devices: signIn.devices, sessions: signIn.sessions, now: now)
        self.settingsStore = settingsStore
        settings = HiveSettingsWorkflow(store: settingsStore, listeners: listeners, now: now)
        auditLog = AuditLog(database: database)
        let servers = ServerStore(database: database)
        self.servers = ServerWorkflow(store: servers, sealer: sealer, now: now)
        jobs = BackupJobWorkflow(store: BackupJobStore(database: database), sealer: sealer, now: now)
        sshKeys = ServerSSHKeyWorkflow(
            store: ServerSSHKeyStore(database: database),
            sealer: sealer,
            settings: settingsStore,
            addresses: addresses,
            now: now
        )
        hostKeys = HostKeyWorkflow(
            store: HostKeyStore(database: database),
            servers: servers,
            scanner: hostKeyScanner,
            pending: PendingHostKeyScans(),
            now: now
        )
        connectionTest = ConnectionTestWorkflow(targets: SSHTargetLoader(database: database, sealer: sealer), ssh: ssh)
        let drives = BackupDriveLocator(store: BackupDriveStore(database: database), volumes: volumes, hiveID: hiveID)
        backupDrive = BackupDriveWorkflow(store: drives.store, volumes: volumes, hiveID: hiveID, now: now)
        runs = BackupRunCoordinator(
            workflow: BackupRunWorkflow(
                hiveID: hiveID,
                database: database,
                drives: drives,
                targets: connectionTest.targets,
                rsync: rsync,
                dumps: dumps,
                passwords: DatabasePasswordLoader(database: database, sealer: sealer),
                origin: origin,
                now: now
            ),
            retention: RetentionWorkflow(database: database, drives: drives, calendar: calendar, now: now),
            sleep: sleepPrevention,
            startupDriveGrace: startupDriveGrace,
            pause: pause
        )
        let schedule = ScheduleCalendar(calendar: calendar)
        jobStatus = JobStatusReader(database: database, runs: runs, schedule: schedule, now: now)
        jobLog = JobLog(database: database)
        scheduler = BackupScheduler(database: database, schedule: schedule, runs: runs, now: now)
        self.fullDiskAccess = fullDiskAccess
        self.macSleep = macSleep
    }
}
