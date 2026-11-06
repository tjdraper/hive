import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct RequestGateTests {
    private static let protectedPath = "/protected"

    private let fixture: SignInFixture
    private let api: APIFixture

    init() throws {
        api = try APIFixture()
        fixture = api.signIn
    }

    /// The real routes, plus one that needs signing in and answers with the device that's signed in.
    private var application: some ApplicationProtocol {
        let router = APIServer.router(api: api.api)
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
            HiveEndpoint.overview,
            HiveEndpoint.devices,
            HiveEndpoint.settings,
            HiveEndpoint.auditLog,
            HiveEndpoint.servers,
            HiveEndpoint.server(UUID()),
            HiveEndpoint.jobs,
            HiveEndpoint.jobs(onServer: UUID()),
            HiveEndpoint.job(UUID()),
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

    @Test(
        "Changes are refused without signing in, and change nothing",
        arguments: [
            (HiveEndpoint.settings, HTTPRequest.Method.put),
            (HiveEndpoint.device(UUID()), .delete),
            (HiveEndpoint.devices, .delete),
        ]
    )
    func changesAreRefused(path: String, method: HTTPRequest.Method) async throws {
        // Arrange
        let settings = HiveSettings(name: "Taken Over", networkAccess: .allAddresses, port: 5000)
        let body = ByteBuffer(bytes: try JSONEncoder().encode(settings))

        // Act
        try await application.test(.router) { client in
            try await client.execute(uri: path, method: method, body: body) { response in
                // Assert
                #expect(response.status == .unauthorized)
            }
        }

        // Assert
        #expect(try api.settings.settings().name == "Test Hive")
        #expect(api.listeners.applied.isEmpty)
        #expect(try fixture.devices.device(id: fixture.device.id) != nil)
    }

    @Test("Servers and jobs can't be added, changed or removed without signing in")
    func configurationChangesAreRefused() async throws {
        // Arrange
        let server = try await api.addServer()
        let job = try await api.addJob(to: server)
        let before = try api.auditEvents()
        let requests: [(String, HTTPRequest.Method)] = [
            (HiveEndpoint.servers, .post),
            (HiveEndpoint.server(server.id), .put),
            (HiveEndpoint.server(server.id), .delete),
            (HiveEndpoint.jobs(onServer: server.id), .post),
            (HiveEndpoint.job(job.id), .put),
            (HiveEndpoint.job(job.id), .delete),
        ]
        // A job is the bigger body, and a server route that got past the gate would answer 400 rather than 401.
        let body = ByteBuffer(bytes: try JSONEncoder().encode(ConfigurationSamples.job(name: "Changed")))

        for (path, method) in requests {
            // Act
            try await application.test(.router) { client in
                try await client.execute(uri: path, method: method, body: body) { response in
                    // Assert
                    #expect(response.status == .unauthorized)
                }
            }
        }

        // Assert
        #expect(try api.servers.all() == [server])
        #expect(try api.jobs.all() == [job])
        #expect(try api.auditEvents() == before)
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
