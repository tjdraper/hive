import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Synchronization

/// A clock tests move by hand.
final class TestClock: Sendable {
    private let date = Mutex(Date(timeIntervalSince1970: 1_800_000_000))

    var now: Date {
        date.withLock { $0 }
    }

    func advance(by interval: TimeInterval) {
        date.withLock { $0 += interval }
    }
}

/// An in-memory Hive with one paired device, whose key is a software key in place of the Secure Enclave.
struct SignInFixture {
    let clock: TestClock
    /// The store's own, as the daemon reads it at start.
    let hiveID: UUID
    let database: HiveDatabase
    let devices: DeviceStore
    let sessions = SessionStore()
    let workflow: SignInWorkflow
    let deviceKey: P256.Signing.PrivateKey
    let device: PairedDevice

    init(apiVersions: APIVersions = .thisBuild) throws {
        clock = TestClock()
        deviceKey = P256.Signing.PrivateKey()
        database = try HiveDatabase.inMemory()
        hiveID = try database.hiveID()
        devices = DeviceStore(database: database)
        let clock = clock
        workflow = SignInWorkflow(
            hiveID: hiveID,
            devices: devices,
            sessions: sessions,
            apiVersions: apiVersions,
            now: { clock.now }
        )
        device = try devices.add(
            name: "Test Mac",
            publicKey: deviceKey.publicKey.x963Representation,
            at: clock.now,
            auditedAs: .pairedOnHiveMac
        )
    }

    /// The same Hive started again, as the daemon does after a restore: the Hive ID read afresh from the
    /// store, and every session forgotten.
    init(restarting other: SignInFixture) throws {
        clock = other.clock
        database = other.database
        hiveID = try database.hiveID()
        devices = other.devices
        deviceKey = other.deviceKey
        device = other.device
        let clock = clock
        workflow = SignInWorkflow(hiveID: hiveID, devices: devices, sessions: sessions, apiVersions: .thisBuild, now: { clock.now })
    }

    /// A sign-in request answering a fresh challenge, signed by `key`.
    func request(
        key: P256.Signing.PrivateKey? = nil,
        deviceID: UUID? = nil,
        challenge: Data? = nil,
        apiVersions: APIVersions = .thisBuild
    ) throws -> SignInRequest {
        let deviceID = deviceID ?? device.id
        let challenge = challenge ?? workflow.issueChallenge().challenge
        let statement = SignInStatement.bytes(hiveID: hiveID, deviceID: deviceID, challenge: challenge)
        return SignInRequest(
            deviceID: deviceID,
            challenge: challenge,
            signature: try (key ?? deviceKey).signature(for: statement).rawRepresentation,
            apiVersions: apiVersions
        )
    }
}

extension SignInOutcome {
    var token: String? {
        guard case .signedIn(let token, _) = self else { return nil }
        return token
    }
}
