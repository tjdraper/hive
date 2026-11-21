#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Crypto
import ScoutProtocol

public enum ScoutSignInError: Error, Equatable {
    /// Hive doesn't know this Scout's key: it was removed, the server was, or the Hive was reset.
    case notRecognized
    case lockedOut
    /// Hive no longer accepts this Scout's protocol version, so Scout has to be updated.
    case protocolNotAccepted(hiveVersion: Int)
    /// A session for another server than the one this Scout enrolled for.
    case wrongServer
    case unexpectedStatus(UInt)
    case unreadableAnswer
}

/// Keeps a Scout signed in: signs in with its saved key when it has no session, and again before the
/// session runs out, so a request never goes out with a session about to end.
public struct ScoutSessionKeeper {
    /// Signing in again this long before the session ends leaves room for a slow request.
    static let renewalMargin: Duration = .seconds(60)

    let enrollment: SavedEnrollment
    let now: () -> ContinuousClock.Instant
    private var session: (token: String, renewAt: ContinuousClock.Instant)?

    public init(enrollment: SavedEnrollment) {
        self.init(enrollment: enrollment, now: { ContinuousClock.now })
    }

    init(enrollment: SavedEnrollment, now: @escaping () -> ContinuousClock.Instant) {
        self.enrollment = enrollment
        self.now = now
    }

    /// A session token, signing in on `connection` first when there's none or it's about to end.
    public mutating func token(on connection: any HiveRequesting) async throws -> String {
        if let session, now() < session.renewAt { return session.token }
        let started = now()
        let signedIn = try await signIn(on: connection)
        session = (signedIn.token, started + .seconds(signedIn.expiresInSeconds) - Self.renewalMargin)
        return signedIn.token
    }

    /// After Hive turns the session down, such as when it restarted, so the next request signs in again.
    public mutating func forget() {
        session = nil
    }

    /// Asks Hive which server the session is for, signing in again once if Hive has forgotten it.
    public mutating func checkSession(on connection: any HiveRequesting) async throws {
        var answer = try await connection.send("GET", ScoutEndpoint.session, body: nil, token: token(on: connection))
        if answer.status == 401 {
            forget()
            answer = try await connection.send("GET", ScoutEndpoint.session, body: nil, token: token(on: connection))
        }
        guard answer.status == 200 else { throw ScoutSignInError.unexpectedStatus(answer.status) }
        guard let check = try? JSONDecoder().decode(ScoutSessionCheck.self, from: Data(answer.body)) else {
            throw ScoutSignInError.unreadableAnswer
        }
        guard check.serverID == enrollment.serverID else { throw ScoutSignInError.wrongServer }
    }

    private func signIn(on connection: any HiveRequesting) async throws -> ScoutSession {
        let challengeAnswer = try await connection.send("POST", ScoutEndpoint.signInChallenge, body: [], token: nil)
        let challenge = try Self.decoded(ScoutSignInChallenge.self, from: challengeAnswer)
        let statement = ScoutSignInStatement.bytes(hiveID: enrollment.hiveID, scoutID: enrollment.scoutID, challenge: challenge.challenge)
        let request = ScoutSignInRequest(
            scoutID: enrollment.scoutID,
            challenge: challenge.challenge,
            signature: try enrollment.signingKey().signature(for: statement).rawRepresentation,
            protocolVersion: ScoutProtocolVersion.current,
            scoutVersion: ScoutRelease.version,
            platform: ScoutRelease.platform
        )
        let answer = try await connection.send("POST", ScoutEndpoint.signIn, body: Array(JSONEncoder().encode(request)), token: nil)
        switch answer.status {
        case 401: throw ScoutSignInError.notRecognized
        case 429: throw ScoutSignInError.lockedOut
        case 409:
            let mismatch = try? JSONDecoder().decode(ScoutProtocolMismatch.self, from: Data(answer.body))
            throw ScoutSignInError.protocolNotAccepted(hiveVersion: mismatch?.hiveProtocolVersion ?? 0)
        default: return try Self.decoded(ScoutSession.self, from: answer)
        }
    }

    private static func decoded<Value: Decodable>(_: Value.Type, from answer: HiveAnswer) throws -> Value {
        guard answer.status == 200 else { throw ScoutSignInError.unexpectedStatus(answer.status) }
        guard let value = try? JSONDecoder().decode(Value.self, from: Data(answer.body)) else { throw ScoutSignInError.unreadableAnswer }
        return value
    }
}
