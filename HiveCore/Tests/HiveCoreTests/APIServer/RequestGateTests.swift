@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct RequestGateTests {
    private var application: some ApplicationProtocol {
        Application(responder: APIServer.responder())
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
            "/health/",
            "/Health",
            "/health/extra",
            "//health",
            "/%68ealth",
            "/v1/health",
            "/../health",
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

    @Test("The health check's path is refused for any other method", arguments: [HTTPRequest.Method.post, .put, .delete, .head])
    func otherMethodsAreRefused(method: HTTPRequest.Method) async throws {
        // Act
        try await application.test(.router) { client in
            try await client.execute(uri: HiveEndpoint.health, method: method, body: ByteBuffer(string: "{}")) { response in
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
            try await client.execute(uri: "/devices", method: .get, headers: headers) { response in
                // Assert
                #expect(response.status == .unauthorized)
            }
        }
    }
}
