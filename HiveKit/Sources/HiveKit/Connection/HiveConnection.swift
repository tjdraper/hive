import CryptoKit
import Foundation

public enum HiveConnectionError: Error, Equatable {
    case invalidAddress
    /// The server didn't show the pinned key: the Hive has a new identity, or it isn't that Hive.
    case wrongKey
    case unexpectedStatus(Int)
    case unreadableResponse
    /// Hive turned the sign-in down without saying why, as it does for every failed sign-in.
    case signInRefused
    /// Too many failed sign-ins from this address or device. Hive gives no hint of how long, since
    /// that's the same for everyone.
    case lockedOut
    case incompatible(update: OutdatedApp)
}

/// HTTPS to one Hive, trusting only the pinned key.
public final class HiveConnection: Sendable {
    private let address: HiveAddress
    private let delegate: PinnedSessionDelegate
    private let session: URLSession

    public init(address: HiveAddress, pin: PublicKeyPin) {
        self.address = address
        delegate = PinnedSessionDelegate(pin: pin)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv13
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    deinit {
        // A session keeps its delegate, and itself, until it's invalidated.
        session.invalidateAndCancel()
    }

    public func checkHealth() async throws {
        let (_, response) = try await send(path: HiveEndpoint.health, method: "GET")
        guard response.statusCode == 204 else { throw HiveConnectionError.unexpectedStatus(response.statusCode) }
    }

    /// Answers a fresh challenge with the device's key and returns the session that follows.
    public func signIn(hiveID: UUID, deviceID: UUID, key: some DeviceSigningKey) async throws -> SignInSession {
        let (challengeData, challengeResponse) = try await send(path: HiveEndpoint.signInChallenge, method: "POST")
        try checkSignInStatus(challengeResponse, body: challengeData)
        let challenge = try decode(SignInChallenge.self, from: challengeData)

        let statement = SignInStatement.bytes(hiveID: hiveID, deviceID: deviceID, challenge: challenge.challenge)
        let request = SignInRequest(
            deviceID: deviceID,
            challenge: challenge.challenge,
            signature: try key.signature(for: statement).rawRepresentation,
            apiVersions: .thisBuild
        )
        let (data, response) = try await send(path: HiveEndpoint.signIn, method: "POST", body: try JSONEncoder().encode(request))
        try checkSignInStatus(response, body: data)
        return try decode(SignInSession.self, from: data)
    }

    private func checkSignInStatus(_ response: HTTPURLResponse, body: Data) throws {
        switch response.statusCode {
        case 200:
            return
        case 401:
            throw HiveConnectionError.signInRefused
        case 409:
            throw HiveConnectionError.incompatible(update: try decode(APIVersionMismatch.self, from: body).update)
        case 429:
            throw HiveConnectionError.lockedOut
        default:
            throw HiveConnectionError.unexpectedStatus(response.statusCode)
        }
    }

    func decode<Value: Decodable>(_: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw HiveConnectionError.unreadableResponse
        }
    }

    func send(
        path: String,
        method: String,
        body: Data? = nil,
        token: String? = nil,
        confirmation: ConfirmationProof? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var request = try request(path: path, method: method, body: body, token: token)
        if let confirmation {
            request.setValue(confirmation.headerValue, forHTTPHeaderField: ConfirmationProof.headerName)
        }
        let (data, response) = try await refusingWrongKey { try await session.data(for: request) }
        guard let response = response as? HTTPURLResponse else { throw HiveConnectionError.unexpectedStatus(0) }
        return (data, response)
    }

    /// A `GET` whose body is read as it arrives.
    func stream(path: String, token: String) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let request = try request(path: path, method: "GET", body: nil, token: token)
        let (bytes, response) = try await refusingWrongKey { try await session.bytes(for: request) }
        guard let response = response as? HTTPURLResponse else { throw HiveConnectionError.unexpectedStatus(0) }
        return (bytes, response)
    }

    private func request(path: String, method: String, body: Data?, token: String?) throws -> URLRequest {
        guard let url = address.url(path: path) else { throw HiveConnectionError.invalidAddress }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// URLSession reports a refused key as a cancelled request.
    private func refusingWrongKey<Value>(_ load: () async throws -> Value) async throws -> Value {
        do {
            return try await load()
        } catch let error as URLError where error.code == .cancelled && delegate.refusedKey {
            throw HiveConnectionError.wrongKey
        }
    }
}
