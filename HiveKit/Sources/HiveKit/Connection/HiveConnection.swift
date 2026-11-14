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

/// HTTPS to one Hive, trusting only the pinned key, at whichever of its addresses answers. Requests go
/// to the address that last worked. Without one, or once it stops answering, every address is asked at
/// once and the first to answer is used (`ReachableAddressResolver`), so an address on a network the
/// device isn't on costs a few seconds rather than a request's whole timeout. Addresses found on the
/// local network (`LocalNetworkService`) are asked alongside the Hive's own.
public final class HiveConnection: Sendable {
    /// Long enough for Tailscale to set up a connection it doesn't have yet, short enough that an
    /// address the device can't reach is given up on quickly.
    private static let probeTimeout: TimeInterval = 5

    private let addresses: [HiveAddress]
    private let discovered: Mutex<[HiveAddress]>
    private let pin: PublicKeyPin
    private let session: URLSession
    private let preferred = PreferredAddressStore()

    public init(addresses: [HiveAddress], pin: PublicKeyPin, discovered: [HiveAddress] = []) {
        self.addresses = addresses
        self.discovered = Mutex(discovered)
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

    /// Replaces the addresses found on the local network, such as when the Hive's advertisement goes away.
    public func useDiscoveredAddresses(_ found: [HiveAddress]) {
        discovered.withLock { $0 = found }
    }

    public func checkHealth() async throws {
        let (_, response) = try await send(path: HiveEndpoint.health, method: "GET")
        guard response.statusCode == 204 else { throw HiveConnectionError.unexpectedStatus(response.statusCode) }
    }

    /// Answers a fresh challenge with the device's key and returns the session that follows.
    public func signIn(hiveID: UUID, deviceID: UUID, key: some DeviceSigningKey, build: BeekeeperBuild?) async throws -> SignInSession {
        let (challengeData, challengeResponse) = try await send(path: HiveEndpoint.signInChallenge, method: "POST")
        try checkSignInStatus(challengeResponse, body: challengeData)
        let challenge = try decode(SignInChallenge.self, from: challengeData)

        let statement = SignInStatement.bytes(hiveID: hiveID, deviceID: deviceID, challenge: challenge.challenge)
        let request = SignInRequest(
            deviceID: deviceID,
            challenge: challenge.challenge,
            signature: try key.signature(for: statement).rawRepresentation,
            apiVersions: .thisBuild,
            build: build
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
        try await atReachableAddress(method: method, probe: probe) { address in
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
        try await atReachableAddress(method: "GET", probe: probe) { address in
            let request = try request(to: address, path: path, method: "GET", body: nil, token: token)
            let delegate = PinnedTaskDelegate(pin: pin)
            let (bytes, response) = try await refusingWrongKey(delegate) { try await session.bytes(for: request, delegate: delegate) }
            guard let response = response as? HTTPURLResponse else { throw HiveConnectionError.unexpectedStatus(0) }
            return (bytes, response)
        }
    }

    /// Sends `attempt` to the address that last worked, or else to the first that answers `probe`. Only a
    /// request that can't have reached Hive is sent again (`neverArrived`), so a `POST` that timed out at
    /// the remembered address fails rather than risk being made twice.
    func atReachableAddress<Value>(
        method: String,
        probe: @escaping @Sendable (HiveAddress) async throws -> Void,
        _ attempt: (HiveAddress) async throws -> Value
    ) async throws -> Value {
        let candidates = candidates()
        if let known = preferred.address, candidates.contains(where: { $0.address == known }) {
            do {
                return try await attempt(known)
            } catch let error where Self.unreachable(error) {
                preferred.forget(known)
                guard Self.neverArrived(error, method: method) else { throw error }
            }
        }
        let address = try await ReachableAddressResolver(candidates: candidates, probe: probe).firstToAnswer()
        preferred.remember(address)
        do {
            return try await attempt(address)
        } catch let error where Self.unreachable(error) {
            preferred.forget(address)
            throw error
        }
    }

    private func candidates() -> [ReachableAddressResolver.Candidate] {
        let found = discovered.withLock { $0 }.filter { !addresses.contains($0) }
        return found.map { .init(address: $0, isDiscovered: true) } + addresses.map { .init(address: $0, isDiscovered: false) }
    }

    /// Any answer over a connection showing the pinned key means the Hive is there.
    private func probe(_ address: HiveAddress) async throws {
        var request = try request(to: address, path: HiveEndpoint.health, method: "GET", body: nil, token: nil)
        request.timeoutInterval = Self.probeTimeout
        let delegate = PinnedTaskDelegate(pin: pin)
        _ = try await refusingWrongKey(delegate) { try await session.data(for: request, delegate: delegate) }
    }

    /// Errors after which the request can be sent to another address without being made twice. A
    /// request that timed out may have reached Hive, so only a `GET` is tried again after one.
    private static func neverArrived(_ error: any Error, method: String) -> Bool {
        switch error {
        case HiveConnectionError.wrongKey:
            true
        case let error as URLError:
            switch error.code {
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet, .secureConnectionFailed:
                true
            case .timedOut:
                method == "GET"
            default:
                false
            }
        default:
            false
        }
    }

    /// Errors that say the address may no longer lead to the Hive, such as after the device moved to
    /// another network.
    private static func unreachable(_ error: any Error) -> Bool {
        neverArrived(error, method: "GET") || (error as? URLError)?.code == .networkConnectionLost
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
