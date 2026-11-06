import Foundation

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
    /// Checked on every request, since it can be turned off while Hive runs.
    let fullDiskAccess: @Sendable () -> FullDiskAccess

    public init(
        hiveID: UUID,
        database: HiveDatabase,
        settings: HiveSettingsStore,
        listeners: ListenerCoordinator,
        sealer: SecretSealer
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
        now: @escaping @Sendable () -> Date
    ) {
        self.hiveID = hiveID
        self.signIn = signIn
        devices = signIn.devices
        revocation = DeviceRevocationWorkflow(devices: signIn.devices, sessions: signIn.sessions, now: now)
        self.settingsStore = settingsStore
        settings = HiveSettingsWorkflow(store: settingsStore, listeners: listeners, now: now)
        auditLog = AuditLog(database: database)
        servers = ServerWorkflow(store: ServerStore(database: database), now: now)
        jobs = BackupJobWorkflow(store: BackupJobStore(database: database), sealer: sealer, now: now)
        self.fullDiskAccess = fullDiskAccess
    }
}
