import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import ScoutProtocol

/// A Scout as the tests make one: a software key, and the ID Hive gave it when it enrolled.
struct TestScout {
    let enrollment: ScoutEnrollment
    let key: P256.Signing.PrivateKey
}

extension APIFixture {
    /// A second server, for checking that one server's Scout never affects another's.
    func addOtherServer() async throws -> Server {
        try await addServer(ServerDraft(name: "Other", connection: ServerConnection(host: "other.example.com", user: "u"), quotaBytes: nil))
    }

    func openEnrollmentWindow(for server: Server) async throws -> EnrollmentWindow {
        let answer = try await sendConfirmed(.post, HiveEndpoint.enrollmentWindow(forServer: server.id))
        guard answer.status == .created else { throw APIFixtureError.unexpectedStatus(answer.status) }
        return try answer.decoded(as: EnrollmentWindow.self)
    }

    func enrollmentRequest(
        code: String,
        key: P256.Signing.PrivateKey = P256.Signing.PrivateKey(),
        protocolVersion: Int = ScoutProtocolVersion.current
    ) throws -> ScoutEnrollmentRequest {
        guard let code = EnrollmentCode(text: code) else { throw APIFixtureError.unexpectedStatus(.badRequest) }
        return ScoutEnrollmentRequest(token: code.token, scoutPublicKey: key.publicKey.x963Representation, protocolVersion: protocolVersion)
    }

    /// Without a session, as every Scout that enrolls is.
    func sendEnrollment(_ request: ScoutEnrollmentRequest) async throws -> APIAnswer {
        try await sendOpen(.post, ScoutEndpoint.enrollment, body: JSONEncoder().encode(request))
    }

    /// Opens a window for the server and enrolls a new Scout through it.
    func enrollScout(for server: Server) async throws -> TestScout {
        let window = try await openEnrollmentWindow(for: server)
        let key = P256.Signing.PrivateKey()
        let answer = try await sendEnrollment(enrollmentRequest(code: window.code, key: key))
        guard answer.status == .ok else { throw APIFixtureError.unexpectedStatus(answer.status) }
        return TestScout(enrollment: try answer.decoded(as: ScoutEnrollment.self), key: key)
    }

    func scoutSignInRequest(
        _ scout: TestScout,
        key: P256.Signing.PrivateKey? = nil,
        protocolVersion: Int = ScoutProtocolVersion.current
    ) -> ScoutSignInRequest {
        let challenge = signIn.workflow.issueChallenge().challenge
        let statement = ScoutSignInStatement.bytes(hiveID: signIn.hiveID, scoutID: scout.enrollment.scoutID, challenge: challenge)
        return ScoutSignInRequest(
            scoutID: scout.enrollment.scoutID,
            challenge: challenge,
            signature: (try? (key ?? scout.key).signature(for: statement).rawRepresentation) ?? Data(),
            protocolVersion: protocolVersion,
            scoutVersion: "0.1.0",
            platform: "linux-x86_64"
        )
    }

    /// Through the sign-in route devices use.
    func sendScoutSignIn(_ request: ScoutSignInRequest) async throws -> APIAnswer {
        try await sendOpen(.post, ScoutEndpoint.signIn, body: JSONEncoder().encode(request))
    }

    func scoutToken(_ scout: TestScout) async throws -> String {
        let answer = try await sendScoutSignIn(scoutSignInRequest(scout))
        guard answer.status == .ok else { throw APIFixtureError.unexpectedStatus(answer.status) }
        return try answer.decoded(as: ScoutSession.self).token
    }

    /// Sends a request with a session token, a Scout's or a device's.
    func send(_ method: HTTPRequest.Method, _ path: String, token: String, body: Data? = nil) async throws -> APIAnswer {
        try await application.test(.router) { [headers = headers(token: token)] client in
            try await client.execute(uri: path, method: method, headers: headers, body: body.map { ByteBuffer(bytes: $0) }) {
                APIAnswer(status: $0.status, body: Data($0.body.readableBytesView))
            }
        }
    }

    private func sendOpen(_ method: HTTPRequest.Method, _ path: String, body: Data) async throws -> APIAnswer {
        try await application.test(.router) { client in
            try await client.execute(uri: path, method: method, body: ByteBuffer(bytes: body)) {
                APIAnswer(status: $0.status, body: Data($0.body.readableBytesView))
            }
        }
    }
}
