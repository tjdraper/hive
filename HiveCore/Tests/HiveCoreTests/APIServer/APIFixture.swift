import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Synchronization

/// Stands in for `ListenerCoordinator`, recording what it was asked to listen on.
final class FakeListenerControl: ListenerControl {
    private let state = Mutex<(applied: [ListenTarget], refuseLoopback: Bool)>(([], false))

    var applied: [ListenTarget] {
        state.withLock { $0.applied }
    }

    /// Makes the next changes fail as if the port were taken on `127.0.0.1`.
    func refuseLoopback() {
        state.withLock { $0.refuseLoopback = true }
    }

    func apply(_ target: ListenTarget) async throws {
        try state.withLock { state in
            if state.refuseLoopback { throw ListenerCoordinatorError.loopbackUnavailable }
            state.applied.append(target)
        }
    }

    func listeningHosts() async -> [String] {
        [ListenerAddress.loopbackHost]
    }
}

/// What opening the file Full Disk Access guards gives: 0 when it opens, or an error number.
final class FakeFullDiskAccess: Sendable {
    private let result = Mutex<Int32>(0)

    var openResult: Int32 {
        result.withLock { $0 }
    }

    func set(_ openResult: Int32) {
        result.withLock { $0 = openResult }
    }
}

/// Stands in for `ssh` and `ssh-keyscan`, answering what it's told and recording what it was asked.
final class FakeSSH: SSHRunning, HostKeyScanning {
    struct State {
        var scan = HostKeyScanOutcome.failed(.unreachable)
        var result = ChildProcess.Result(status: 0, standardOutput: Data(), standardError: Data())
        var scanned: [ServerConnection] = []
        var ran: [(command: String, target: SSHTarget)] = []
    }

    private let state = Mutex(State())

    var scanned: [ServerConnection] {
        state.withLock { $0.scanned }
    }

    var ran: [(command: String, target: SSHTarget)] {
        state.withLock { $0.ran }
    }

    func setScan(_ outcome: HostKeyScanOutcome) {
        state.withLock { $0.scan = outcome }
    }

    func setResult(status: Int32, standardError: String = "") {
        state.withLock { $0.result = ChildProcess.Result(status: status, standardOutput: Data(), standardError: Data(standardError.utf8)) }
    }

    func scan(_ connection: ServerConnection) async throws -> HostKeyScanOutcome {
        state.withLock { state in
            state.scanned.append(connection)
            return state.scan
        }
    }

    func run(_ remoteCommand: String, on target: SSHTarget) async throws -> ChildProcess.Result {
        state.withLock { state in
            state.ran.append((remoteCommand, target))
            return state.result
        }
    }
}

/// The Mac's addresses, as the fixture's Hive sees them.
final class FakeMacAddresses: Sendable {
    private let addresses = Mutex(["100.64.0.7", "192.168.1.20"])

    var current: [String] {
        addresses.withLock { $0 }
    }

    func set(_ new: [String]) {
        addresses.withLock { $0 = new }
    }
}

/// The Mac's mounted volumes, as the fixture's Hive sees them: folders the test makes.
final class FakeVolumes: VolumeListing {
    private let volumes = Mutex<[MountedVolume]>([])

    var current: [MountedVolume] {
        volumes.withLock { $0 }
    }

    func set(_ new: [MountedVolume]) {
        volumes.withLock { $0 = new }
    }

    func mountedVolumes() -> [MountedVolume] {
        current
    }
}

/// Counts the power assertions a run takes and lets go of.
final class FakeSleepPrevention: SleepPreventing {
    private let counts = Mutex((taken: 0, held: 0))

    var taken: Int {
        counts.withLock { $0.taken }
    }

    var held: Int {
        counts.withLock { $0.held }
    }

    func preventSleep() -> @Sendable () -> Void {
        counts.withLock {
            $0.taken += 1
            $0.held += 1
        }
        return { self.counts.withLock { $0.held -= 1 } }
    }
}

/// Counts the pauses a run makes waiting for the backup drive, and does what it's told at each. A
/// pause moves the fixture's clock on instead of sleeping, but still lets other work in, as a real
/// one would.
final class FakePauses: Sendable {
    private struct State {
        var count = 0
        var action: (@Sendable (Int) -> Void)?
        var realDelay: Duration?
    }

    private let state = Mutex(State())

    var count: Int {
        state.withLock { $0.count }
    }

    /// `action` gets how many pauses there have been, this one included.
    func onEach(_ action: @escaping @Sendable (Int) -> Void) {
        state.withLock { $0.action = action }
    }

    /// Makes each pause take `delay` of real time too, so a test can catch a run while it waits.
    func takeRealTime(_ delay: Duration) {
        state.withLock { $0.realDelay = delay }
    }

    func pause() async throws {
        let (count, action, delay) = state.withLock { state in
            state.count += 1
            return (state.count, state.action, state.realDelay)
        }
        action?(count)
        if let delay {
            try await Task.sleep(for: delay)
        } else {
            await Task.yield()
        }
    }
}

/// The whole API over an in-memory Hive with one signed-in device.
struct APIFixture {
    /// Schedules are worked out in a time zone with daylight saving, whatever the Mac running the tests uses.
    static let timeZone = TimeZone(identifier: "America/New_York") ?? .gmt

    static let defaultPort = 4483

    let signIn: SignInFixture
    let listeners = FakeListenerControl()
    let settings: HiveSettingsStore
    let auditLog: AuditLog
    let api: HiveAPI
    let fullDiskAccess = FakeFullDiskAccess()
    let sealer: SecretSealer
    let ssh = FakeSSH()
    let addresses = FakeMacAddresses()
    let volumes = FakeVolumes()
    let sleepPrevention = FakeSleepPrevention()
    let pauses = FakePauses()

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// `dumpSearchPath` is where database dumps find `docker` and the dump tools, which tests stand in
    /// for with scripts. Runs wait for the backup drive only within `startupDriveGrace` of the fixture's
    /// start, and waiting moves the clock on rather than sleeping. Sharing `signIn` and `sealer` with
    /// another fixture starts the same Hive again.
    init(
        signIn: SignInFixture? = nil,
        sealer: SecretSealer? = nil,
        dumpSearchPath: String = "/usr/bin:/bin",
        startupDriveGrace: TimeInterval = 0
    ) throws {
        self.signIn = try signIn ?? SignInFixture()
        let sealer = sealer ?? SecretSealer(key: P256.KeyAgreement.PrivateKey())
        self.sealer = sealer
        let signIn = self.signIn
        settings = HiveSettingsStore(database: signIn.database, defaultPort: Self.defaultPort)
        auditLog = AuditLog(database: signIn.database)
        let clock = signIn.clock
        api = HiveAPI(
            hiveID: signIn.hiveID,
            database: signIn.database,
            signIn: signIn.workflow,
            settingsStore: settings,
            listeners: listeners,
            sealer: sealer,
            fullDiskAccess: { [fullDiskAccess] in FullDiskAccessProbe { _ in fullDiskAccess.openResult }.check() },
            ssh: ssh,
            hostKeyScanner: ssh,
            addresses: { [addresses] in addresses.current },
            volumes: volumes,
            rsync: RsyncRunner(rsync: TestRsync.url),
            dumps: DatabaseDumpRunner(localSearchPath: dumpSearchPath),
            // Directories and dumps are read from folders and scripts the tests make on this Mac, never over `ssh`.
            origin: { _ in .thisMac },
            calendar: Self.calendar,
            sleepPrevention: sleepPrevention,
            macSleep: { .afterIdle(minutes: 10) },
            startupDriveGrace: startupDriveGrace,
            pause: { [pauses] in
                clock.advance(by: TimeInterval($0.components.seconds))
                try await pauses.pause()
            },
            now: { clock.now }
        )
    }

    var application: some ApplicationProtocol {
        Application(responder: APIServer.responder(api: api))
    }

    /// A session token for the fixture's device, or for `device` signed with `key`.
    func token(for device: PairedDevice? = nil, key: P256.Signing.PrivateKey? = nil) throws -> String {
        let request = try signIn.request(key: key, deviceID: device?.id)
        guard let token = signIn.workflow.signIn(request, from: ClientAddress(key: "local")).token else {
            throw APIFixtureError.couldNotSignIn
        }
        return token
    }

    func headers(token: String) -> HTTPFields {
        [.authorization: "Bearer \(token)"]
    }

    func auditEvents() throws -> [AuditEvent] {
        try auditLog.page(before: nil, limit: AuditLog.largestPage).entries.map(\.event)
    }

    /// Sends a request as the fixture's device.
    func send(_ method: HTTPRequest.Method, _ path: String, body: Data? = nil) async throws -> APIAnswer {
        let token = try token()
        return try await application.test(.router) { client in
            try await client.execute(uri: path, method: method, headers: headers(token: token), body: body.map { ByteBuffer(bytes: $0) }) {
                APIAnswer(status: $0.status, body: Data($0.body.readableBytesView))
            }
        }
    }

    func send(_ method: HTTPRequest.Method, _ path: String, json: some Encodable) async throws -> APIAnswer {
        try await send(method, path, body: JSONEncoder().encode(json))
    }
}

struct APIAnswer {
    let status: HTTPResponse.Status
    let body: Data

    func decoded<Value: Decodable>(as _: Value.Type) throws -> Value {
        try JSONDecoder().decode(Value.self, from: body)
    }

    /// The problems in a 422 refusal.
    var problems: [ConfigurationProblem] {
        get throws { try decoded(as: ConfigurationRefusal.self).problems }
    }
}

enum APIFixtureError: Error {
    case couldNotSignIn
    case unexpectedStatus(HTTPResponse.Status)
}

extension TestResponse {
    func decoded<Value: Decodable>(as _: Value.Type) throws -> Value {
        try JSONDecoder().decode(Value.self, from: Data(body.readableBytesView))
    }
}
