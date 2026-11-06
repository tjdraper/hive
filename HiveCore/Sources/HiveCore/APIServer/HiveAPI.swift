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
    let sshKeys: ServerSSHKeyWorkflow
    let hostKeys: HostKeyWorkflow
    let connectionTest: ConnectionTestWorkflow
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
            ssh: SSHRunner(),
            hostKeyScanner: HostKeyScanner(),
            addresses: { NetworkInterfaceList.presentAddresses().sorted() },
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
        addresses: @escaping @Sendable () -> [String],
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
        self.fullDiskAccess = fullDiskAccess
    }
}
