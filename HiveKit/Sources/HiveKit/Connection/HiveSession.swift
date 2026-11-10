import Foundation

/// An answer Hive gave other than the one asked for, such as 404 for a device that's already gone.
public struct HiveRequestError: Error, Equatable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// A signed-in connection to one Hive. It signs in when it has no session or its session is about to run
/// out, and once more when Hive answers 401, since Hive forgets every session when it restarts.
public actor HiveSession {
    /// Sign in this long before the session runs out, so a request never arrives just after it has.
    static let renewalMargin: TimeInterval = 30

    private let connection: HiveConnection
    private let hiveID: UUID
    private let deviceID: UUID
    private let key: any DeviceSigningKey
    private var session: (token: String, expiresAt: Date)?
    private var signingIn: Task<String, any Error>?

    public init(connection: HiveConnection, hiveID: UUID, deviceID: UUID, key: any DeviceSigningKey) {
        self.connection = connection
        self.hiveID = hiveID
        self.deviceID = deviceID
        self.key = key
    }

    public func checkHealth() async throws {
        try await connection.checkHealth()
    }

    /// Signs in now, whether or not the current session is still good.
    public func signIn() async throws {
        session = nil
        _ = try await token()
    }

    public func get<Response: Decodable>(_ path: String, as _: Response.Type = Response.self) async throws -> Response {
        try await decoded(send(method: "GET", path: path))
    }

    public func put<Response: Decodable>(
        _ path: String,
        body: some Encodable,
        as _: Response.Type = Response.self
    ) async throws -> Response {
        try await decoded(send(method: "PUT", path: path, body: JSONEncoder().encode(body)))
    }

    public func post<Response: Decodable>(
        _ path: String,
        body: some Encodable,
        as _: Response.Type = Response.self
    ) async throws -> Response {
        try await decoded(send(method: "POST", path: path, body: JSONEncoder().encode(body)))
    }

    /// For an action that takes nothing, such as a scan or a test.
    public func post<Response: Decodable>(_ path: String, as _: Response.Type = Response.self) async throws -> Response {
        try await decoded(send(method: "POST", path: path))
    }

    public func delete(_ path: String) async throws {
        _ = try await checked(send(method: "DELETE", path: path))
    }

    /// Any request, with whatever Hive answers, such as for the Developer window, which shows the answer
    /// as it is. `confirmation` is signed over exactly this method, path and body.
    public func send(
        method: String,
        path: String,
        body: Data? = nil,
        confirmation: ConfirmationProof? = nil
    ) async throws -> (status: Int, body: Data) {
        let (data, response) = try await sendSignedIn(method: method, path: path, body: body, confirmation: confirmation)
        return (response.statusCode, data)
    }

    /// Hive's live updates, as they come, until Hive ends the response, such as when the session runs out.
    public func liveUpdates() async throws -> AsyncThrowingStream<LiveUpdate, any Error> {
        var (bytes, response) = try await connection.stream(path: HiveEndpoint.liveUpdates, token: token())
        if response.statusCode == 401 {
            session = nil
            (bytes, response) = try await connection.stream(path: HiveEndpoint.liveUpdates, token: token())
        }
        guard response.statusCode == 200 else { throw HiveRequestError(status: response.statusCode, body: Data()) }

        let lines = bytes.lines
        let connection = connection
        return AsyncThrowingStream { continuation in
            let reading = Task {
                do {
                    for try await line in lines {
                        continuation.yield(try connection.decode(LiveUpdate.self, from: Data(line.utf8)))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reading.cancel() }
        }
    }

    /// A request turned away for its session never reaches its route, so its confirmation's nonce is
    /// still unused when it's sent again.
    private func sendSignedIn(
        method: String,
        path: String,
        body: Data?,
        confirmation: ConfirmationProof? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let first = try await connection.send(path: path, method: method, body: body, token: token(), confirmation: confirmation)
        guard first.1.statusCode == 401 else { return first }
        session = nil
        return try await connection.send(path: path, method: method, body: body, token: token(), confirmation: confirmation)
    }

    private func checked(_ answer: (status: Int, body: Data)) throws -> Data {
        guard (200 ..< 300).contains(answer.status) else { throw HiveRequestError(status: answer.status, body: answer.body) }
        return answer.body
    }

    private func decoded<Response: Decodable>(_ answer: (status: Int, body: Data)) throws -> Response {
        try connection.decode(Response.self, from: checked(answer))
    }

    /// Requests that arrive while a sign-in is under way wait for it rather than starting their own.
    private func token() async throws -> String {
        if let session, session.expiresAt.timeIntervalSinceNow > Self.renewalMargin { return session.token }
        if let signingIn { return try await signingIn.value }

        let task = Task {
            let signedIn = try await connection.signIn(hiveID: hiveID, deviceID: deviceID, key: key)
            session = (signedIn.token, Date().addingTimeInterval(TimeInterval(signedIn.expiresInSeconds)))
            return signedIn.token
        }
        signingIn = task
        defer { signingIn = nil }
        return try await task.value
    }
}
