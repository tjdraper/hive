import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct SignInRoutesTests {
    private let fixture: SignInFixture

    init() throws {
        fixture = try SignInFixture()
    }

    private var application: some ApplicationProtocol {
        Application(responder: APIServer.responder(signIn: fixture.workflow))
    }

    private func signInBody(for challenge: SignInChallenge, key: P256.Signing.PrivateKey? = nil) throws -> ByteBuffer {
        ByteBuffer(bytes: try JSONEncoder().encode(try fixture.request(key: key, challenge: challenge.challenge)))
    }

    @Test("A device asks for a challenge, signs it, and gets a session that the gate accepts")
    func signsInThroughTheRoutes() async throws {
        try await application.test(.router) { client in
            // Arrange
            let challenge = try await client.execute(uri: HiveEndpoint.signInChallenge, method: .post) { response in
                #expect(response.status == .ok)
                return try JSONDecoder().decode(SignInChallenge.self, from: Data(response.body.readableBytesView))
            }

            // Act
            let session = try await client.execute(
                uri: HiveEndpoint.signIn,
                method: .post,
                body: try signInBody(for: challenge)
            ) { response in
                #expect(response.status == .ok)
                return try JSONDecoder().decode(SignInSession.self, from: Data(response.body.readableBytesView))
            }

            // Assert
            #expect(session.expiresInSeconds == Int(SessionStore.lifetime))
            #expect(session.hiveAPIVersions == .thisBuild)
            try await client.execute(uri: "/anything", method: .get, headers: [.authorization: "Bearer \(session.token)"]) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test("A refused sign-in gets 401 with nothing in the body to say why")
    func refusalSaysNothing() async throws {
        try await application.test(.router) { client in
            // Arrange
            let challenge = try await client.execute(uri: HiveEndpoint.signInChallenge, method: .post) { response in
                try JSONDecoder().decode(SignInChallenge.self, from: Data(response.body.readableBytesView))
            }

            // Act
            try await client.execute(
                uri: HiveEndpoint.signIn,
                method: .post,
                body: try signInBody(for: challenge, key: P256.Signing.PrivateKey())
            ) { response in
                // Assert
                #expect(response.status == .unauthorized)
                #expect(response.body.readableBytes == 0)
            }
        }
    }

    @Test("A body that isn't JSON is refused")
    func malformedBodyIsRefused() async throws {
        // Act
        try await application.test(.router) { client in
            try await client.execute(uri: HiveEndpoint.signIn, method: .post, body: ByteBuffer(string: "not json")) { response in
                // Assert
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("A body larger than any sign-in needs is turned away unread")
    func largeBodyIsRefused() async throws {
        // Arrange
        let body = ByteBuffer(repeating: UInt8(ascii: "a"), count: SignInRoutes.largestBody + 1)

        // Act
        try await application.test(.router) { client in
            try await client.execute(uri: HiveEndpoint.signIn, method: .post, body: body) { response in
                // Assert
                #expect(response.status == .contentTooLarge)
            }
        }
    }

    @Test("Once locked out, the sign-in route answers 429")
    func lockedOutGets429() async throws {
        try await application.test(.router) { client in
            // Arrange
            for _ in 0 ..< FailedAttemptPolicy.signIn.maximumFailures {
                let status = try await client.execute(uri: HiveEndpoint.signIn, method: .post, body: ByteBuffer(string: "{}")) { $0.status }
                #expect(status == .unauthorized)
            }

            // Act
            try await client.execute(uri: HiveEndpoint.signIn, method: .post, body: ByteBuffer(string: "{}")) { response in
                // Assert
                #expect(response.status == .tooManyRequests)
            }
        }
    }

    @Test("An incompatible Beekeeper gets 409 saying which app to update")
    func incompatibleGets409() async throws {
        // Arrange
        let fixture = try SignInFixture(apiVersions: APIVersions(current: 2, oldestCompatible: 2))
        let application = Application(responder: APIServer.responder(signIn: fixture.workflow))
        let request = try fixture.request(apiVersions: APIVersions(current: 1, oldestCompatible: 1))

        // Act
        try await application.test(.router) { client in
            try await client.execute(
                uri: HiveEndpoint.signIn,
                method: .post,
                body: ByteBuffer(bytes: try JSONEncoder().encode(request))
            ) { response in
                // Assert
                #expect(response.status == .conflict)
                let mismatch = try JSONDecoder().decode(APIVersionMismatch.self, from: Data(response.body.readableBytesView))
                #expect(mismatch.update == .beekeeper)
            }
        }
    }
}
