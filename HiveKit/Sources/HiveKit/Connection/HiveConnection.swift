import CryptoKit
import Foundation
import Synchronization

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
    /// The pairing code's token isn't good: it was used, it expired, or its window was closed.
    case pairingRefused
}

/// HTTPS to one Hive, trusting only the pinned key, at whichever of its addresses answers. It tries them
/// in order, starting from the last one that worked, and moves on when one can't be reached or shows
/// another key, which may be another machine with the Hive's old address. A key refused at one address
/// and shown at none is the Hive's identity having changed.
public final class HiveConnection: Sendable {
    private let addresses: [HiveAddress]
    private let pin: PublicKeyPin
    private let session: URLSession
    private let preferred = Mutex(0)

    public init(addresses: [HiveAddress], pin: PublicKeyPin) {
        self.addresses = addresses
        self.pin = pin

        let configuration = URLSessionConfiguration.ephemeral
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv13
        configuration.urlCache = nil
        // Without a delegate, so each request's own checks the pin (`PinnedTaskDelegate`).
        session = URLSession(configuration: configuration)
    }

    deinit {
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

    /// Pairs a new device through a pairing window, over this connection pinned to the code's key.
    public func pair(_ request: PairingRequest) async throws -> PairingResult {
        let (data, response) = try await send(path: HiveEndpoint.pairing, method: "POST", body: try JSONEncoder().encode(request))
        switch response.statusCode {
        case 200:
            return try decode(PairingResult.self, from: data)
        case 404:
            throw HiveConnectionError.pairingRefused
        case 409:
            throw HiveConnectionError.incompatible(update: try decode(APIVersionMismatch.self, from: data).update)
        case 429:
            throw HiveConnectionError.lockedOut
        default:
            throw HiveConnectionError.unexpectedStatus(response.statusCode)
        }
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
        try await atEachAddress(method: method) { address in
            var request = try request(to: address, path: path, method: method, body: body, token: token)
            if let confirmation {
                request.setValue(confirmation.headerValue, forHTTPHeaderField: ConfirmationProof.headerName)
            }
            let delegate = PinnedTaskDelegate(pin: pin)
            let (data, response) = try await refusingWrongKey(delegate) { try await session.data(for: request, delegate: delegate) }
            guard let response = response as? HTTPURLResponse else { throw HiveConnectionError.unexpectedStatus(0) }
            return (data, response)
        }
    }

    /// A `GET` whose body is read as it arrives.
    func stream(path: String, token: String) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        try await atEachAddress(method: "GET") { address in
            let request = try request(to: address, path: path, method: "GET", body: nil, token: token)
            let delegate = PinnedTaskDelegate(pin: pin)
            let (bytes, response) = try await refusingWrongKey(delegate) { try await session.bytes(for: request, delegate: delegate) }
            guard let response = response as? HTTPURLResponse else { throw HiveConnectionError.unexpectedStatus(0) }
            return (bytes, response)
        }
    }

    /// Tries `attempt` at each address, from the last one that worked, until one gets an answer.
    private func atEachAddress<Value>(method: String, _ attempt: (HiveAddress) async throws -> Value) async throws -> Value {
        guard !addresses.isEmpty else { throw HiveConnectionError.invalidAddress }
        let first = preferred.withLock { $0 }
        var lastError: (any Error)?
        var sawWrongKey = false
        for offset in addresses.indices {
            let index = (first + offset) % addresses.count
            do {
                let value = try await attempt(addresses[index])
                preferred.withLock { $0 = index }
                return value
            } catch HiveConnectionError.wrongKey {
                sawWrongKey = true
            } catch let error as URLError where Self.neverArrived(error, method: method) {
                lastError = error
            }
        }
        if sawWrongKey { throw HiveConnectionError.wrongKey }
        throw lastError ?? HiveConnectionError.invalidAddress
    }

    /// Errors after which the request can be sent to another address without being made twice. A
    /// request that timed out may have reached Hive, so only a `GET` is tried again after one.
    private static func neverArrived(_ error: URLError, method: String) -> Bool {
        switch error.code {
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet, .secureConnectionFailed:
            true
        case .timedOut:
            method == "GET"
        default:
            false
        }
    }

    private func request(to address: HiveAddress, path: String, method: String, body: Data?, token: String?) throws -> URLRequest {
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
    private func refusingWrongKey<Value>(_ delegate: PinnedTaskDelegate, _ load: () async throws -> Value) async throws -> Value {
        do {
            return try await load()
        } catch let error as URLError where error.code == .cancelled && delegate.refusedKey {
            throw HiveConnectionError.wrongKey
        }
    }
}
