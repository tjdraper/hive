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

/// The whole API over an in-memory Hive with one signed-in device.
struct APIFixture {
    static let defaultPort = 4483

    let signIn: SignInFixture
    let listeners = FakeListenerControl()
    let settings: HiveSettingsStore
    let auditLog: AuditLog
    let api: HiveAPI
    let fullDiskAccess = FakeFullDiskAccess()
    let sealer = SecretSealer(key: P256.KeyAgreement.PrivateKey())
    let ssh = FakeSSH()
    let addresses = FakeMacAddresses()
    let volumes = FakeVolumes()

    init(signIn: SignInFixture? = nil) throws {
        self.signIn = try signIn ?? SignInFixture()
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
            // Directories are read from folders the tests make on this Mac, never over `ssh`.
            origin: { _ in .thisMac },
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
