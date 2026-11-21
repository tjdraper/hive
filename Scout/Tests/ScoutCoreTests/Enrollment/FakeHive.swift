import Crypto
import Foundation
@testable import ScoutCore
import ScoutProtocol
import Synchronization

/// Stands in for Hive and the network: each address is unreachable, shows another key, or reaches a
/// Hive that answers enrolling and signing in the way the test sets, recording what it was sent.
final class FakeHive: HiveConnecting {
    enum Reach {
        case unreachable
        case otherKey
        case hive
    }

    struct State {
        var reach: [String: Reach] = [:]
        var enrollmentStatus: UInt = 200
        var answeredServerID: UUID?
        var connectedTo: [String] = []
        var enrolledKeys: [Data] = []
        var signIns = 0
        var sessionLifetime = 900
    }

    let hiveID = UUID()
    let serverID = UUID()
    let scoutID = UUID()
    let pin = Data(repeating: 0xAB, count: 32)
    private let state = Mutex(State())

    var connectedTo: [String] {
        state.withLock { $0.connectedTo }
    }

    var enrolledKeys: [Data] {
        state.withLock { $0.enrolledKeys }
    }

    var signIns: Int {
        state.withLock { $0.signIns }
    }

    func set(_ change: (inout State) -> Void) {
        state.withLock { change(&$0) }
    }

    func code(hosts: [String]) -> EnrollmentCode {
        EnrollmentCode(
            hiveID: hiveID,
            serverID: serverID,
            pin: pin,
            token: Data(repeating: 7, count: EnrollmentCode.tokenLength),
            addresses: hosts.map { EnrollmentCode.Address(host: $0, port: 4483) }
        )
    }

    func withConnection<Result>(
        to address: HiveAddress,
        pin: HiveKeyPin,
        _ body: (any HiveRequesting) async throws -> Result
    ) async throws -> Result {
        let reach = state.withLock { state in
            state.connectedTo.append(address.host)
            return state.reach[address.host] ?? .hive
        }
        switch reach {
        case .unreachable: throw HostLookupError.noAddresses
        case .otherKey: throw HiveConnectionError.keyNotPinned
        case .hive:
            guard pin.sha256 == Array(self.pin) else { throw HiveConnectionError.keyNotPinned }
            return try await body(Connection(hive: self))
        }
    }

    private struct Connection: HiveRequesting {
        let hive: FakeHive

        func send(_ method: String, _ path: String, body: [UInt8]?, token: String?) async throws -> HiveAnswer {
            try hive.answer(method, path, body: Data(body ?? []), token: token)
        }
    }

    private static let challenge = Data(repeating: 3, count: 57)
    private static let token = "scout-session"

    private func answer(_ method: String, _ path: String, body: Data, token: String?) throws -> HiveAnswer {
        switch (method, path) {
        case ("POST", ScoutEndpoint.enrollment):
            let request = try JSONDecoder().decode(ScoutEnrollmentRequest.self, from: body)
            let (status, serverID) = state.withLock { state in
                if state.enrollmentStatus == 200 { state.enrolledKeys.append(request.scoutPublicKey) }
                return (state.enrollmentStatus, state.answeredServerID ?? self.serverID)
            }
            guard status == 200 else { return HiveAnswer(status: status, body: []) }
            return try json(ScoutEnrollment(hiveID: hiveID, serverID: serverID, scoutID: scoutID))
        case ("POST", ScoutEndpoint.signInChallenge):
            return try json(ScoutSignInChallenge(challenge: Self.challenge, expiresInSeconds: 60))
        case ("POST", ScoutEndpoint.signIn):
            let request = try JSONDecoder().decode(ScoutSignInRequest.self, from: body)
            let statement = ScoutSignInStatement.bytes(hiveID: hiveID, scoutID: request.scoutID, challenge: request.challenge)
            guard let enrolled = enrolledKeys.last,
                  let key = try? P256.Signing.PublicKey(x963Representation: enrolled),
                  let signature = try? P256.Signing.ECDSASignature(rawRepresentation: request.signature),
                  key.isValidSignature(signature, for: statement)
            else { return HiveAnswer(status: 401, body: []) }
            let lifetime = state.withLock { state in
                state.signIns += 1
                return state.sessionLifetime
            }
            return try json(ScoutSession(token: Self.token, expiresInSeconds: lifetime))
        case ("GET", ScoutEndpoint.session):
            guard token == Self.token else { return HiveAnswer(status: 401, body: []) }
            return try json(ScoutSessionCheck(serverID: state.withLock { $0.answeredServerID } ?? serverID))
        default:
            return HiveAnswer(status: 404, body: [])
        }
    }

    private func json(_ value: some Encodable) throws -> HiveAnswer {
        HiveAnswer(status: 200, body: Array(try JSONEncoder().encode(value)))
    }
}
