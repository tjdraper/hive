import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct RequestGateTests {
    private static let protectedPath = "/protected"

    private let fixture: SignInFixture

    init() throws {
        fixture = try SignInFixture()
    }

    /// The real routes, plus one that needs signing in and answers with the device that's signed in.
    private var application: some ApplicationProtocol {
        let router = APIServer.router(signIn: fixture.workflow)
        router.get(RouterPath(Self.protectedPath)) { _, context in
            context.signedInDeviceID?.uuidString ?? "none"
        }
        let gate = RequestGate(next: router.buildResponder(), sessions: fixture.sessions, now: fixture.workflow.now)
        return Application(responder: gate)
    }

    @Test("The health check answers without signing in, with nothing in the body")
    func healthCheckAnswers() async throws {
        // Act
        try await application.test(.router) { client in
            try await client.execute(uri: HiveEndpoint.health, method: .get) { response in
                // Assert
                #expect(response.status == .noContent)
                #expect(response.body.readableBytes == 0)
            }
        }
    }

    @Test(
        "Every other path is refused without signing in, whether or not a route exists for it",
        arguments: [
            "/",
            "/devices",
            protectedPath,
            "/health/",
            "/Health",
            "/health/extra",
            "//health",
            "/%68ealth",
            "/v1/health",
            "/../health",
            "/sign-in/",
            "/sign-in/challenge/",
            "/sign-in/session",
        ]
    )
    func otherPathsAreRefused(path: String) async throws {
        // Act
        try await application.test(.router) { client in
            try await client.execute(uri: path, method: .get) { response in
                // Assert
                #expect(response.status == .unauthorized)
                #expect(response.body.readableBytes == 0)
            }
        }
    }

    @Test(
        "An open route's path is refused for any other method",
        arguments: [
            (HiveEndpoint.health, HTTPRequest.Method.post),
            (HiveEndpoint.health, .put),
            (HiveEndpoint.health, .delete),
            (HiveEndpoint.health, .head),
            (HiveEndpoint.signInChallenge, .get),
            (HiveEndpoint.signIn, .get),
            (HiveEndpoint.signIn, .put),
        ]
    )
    func otherMethodsAreRefused(path: String, method: HTTPRequest.Method) async throws {
        // Act
        try await application.test(.router) { client in
            try await client.execute(uri: path, method: method, body: ByteBuffer(string: "{}")) { response in
                // Assert
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("A made-up session token gets no further than no token at all")
    func madeUpTokenIsRefused() async throws {
        // Arrange
        let headers: HTTPFields = [.authorization: "Bearer not-a-session"]

        // Act
        try await application.test(.router) { client in
            try await client.execute(uri: Self.protectedPath, method: .get, headers: headers) { response in
                // Assert
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("A signed-in device's token reaches the route, which knows which device it is")
    func sessionTokenPasses() async throws {
        // Arrange
        let token = try #require(fixture.workflow.signIn(try fixture.request(), from: ClientAddress(key: "local")).token)
        let headers: HTTPFields = [.authorization: "Bearer \(token)"]

        // Act
        try await application.test(.router) { client in
            try await client.execute(uri: Self.protectedPath, method: .get, headers: headers) { response in
                // Assert
                #expect(response.status == .ok)
                #expect(String(buffer: response.body) == fixture.device.id.uuidString)
            }
        }
    }

    @Test("An expired session token is refused")
    func expiredTokenIsRefused() async throws {
        // Arrange
        let token = try #require(fixture.workflow.signIn(try fixture.request(), from: ClientAddress(key: "local")).token)
        fixture.clock.advance(by: SessionStore.lifetime)
        let headers: HTTPFields = [.authorization: "Bearer \(token)"]

        // Act
        try await application.test(.router) { client in
            try await client.execute(uri: Self.protectedPath, method: .get, headers: headers) { response in
                // Assert
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("A token sent some other way than as a bearer token is refused")
    func tokenMustBeBearer() async throws {
        // Arrange
        let token = try #require(fixture.workflow.signIn(try fixture.request(), from: ClientAddress(key: "local")).token)
        let headers: HTTPFields = [.authorization: "Basic \(token)", .cookie: "token=\(token)"]

        // Act
        try await application.test(.router) { client in
            try await client.execute(uri: Self.protectedPath, method: .get, headers: headers) { response in
                // Assert
                #expect(response.status == .unauthorized)
            }
        }
    }
}
