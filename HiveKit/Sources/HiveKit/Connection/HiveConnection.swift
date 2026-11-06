import Foundation

public enum HiveConnectionError: Error, Equatable {
    case invalidAddress
    /// The server didn't show the pinned key: the Hive has a new identity, or it isn't that Hive.
    case wrongKey
    case unexpectedStatus(Int)
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
        let response = try await send(path: HiveEndpoint.health)
        guard response.statusCode == 204 else { throw HiveConnectionError.unexpectedStatus(response.statusCode) }
    }

    private func send(path: String) async throws -> HTTPURLResponse {
        guard let url = address.url(path: path) else { throw HiveConnectionError.invalidAddress }

        let response: URLResponse
        do {
            (_, response) = try await session.data(from: url)
        } catch let error as URLError where error.code == .cancelled && delegate.refusedKey {
            throw HiveConnectionError.wrongKey
        }

        guard let response = response as? HTTPURLResponse else { throw HiveConnectionError.unexpectedStatus(0) }
        return response
    }
}
