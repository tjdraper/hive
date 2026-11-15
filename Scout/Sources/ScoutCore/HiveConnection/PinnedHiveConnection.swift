import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import Synchronization

public enum HiveConnectionError: Error, Equatable {
    /// The server's key isn't the pinned one. Scout never sends to it, whatever else it offers.
    case keyNotPinned
    case unexpectedStatus(UInt)
    case closedByHive
}

/// A TLS 1.3 connection to Hive that accepts only the pinned identity key, kept open for a run of
/// requests.
public final class PinnedHiveConnection {
    private typealias Channel = NIOAsyncChannel<HTTPClientResponsePart, HTTPClientRequestPart>

    /// Hive's certificate is self-signed and Scout reaches it at addresses the certificate can't name,
    /// so the pin replaces chain and hostname checks. The TLS handshake has already proved Hive holds
    /// the private half of the key it presented, so the key is all that needs checking.
    private static let tlsConfiguration: TLSConfiguration = {
        var configuration = TLSConfiguration.makeClientConfiguration()
        configuration.minimumTLSVersion = .tlsv13
        configuration.maximumTLSVersion = .tlsv13
        // `.none` would skip the pin callback too, so hostname checks are the only part turned off.
        configuration.certificateVerification = .noHostnameVerification
        // The pin callback replaces trust roots, so none are loaded, which also spares their memory.
        configuration.trustRoots = .certificates([])
        return configuration
    }()

    /// Set by the pin check, so a refused key can be told apart from the handshake failure it causes.
    private final class PinRefusal: Sendable {
        private let refused = Mutex(false)

        var happened: Bool {
            refused.withLock { $0 }
        }

        func record() {
            refused.withLock { $0 = true }
        }
    }

    private let address: HiveAddress
    private let outbound: NIOAsyncChannelOutboundWriter<HTTPClientRequestPart>
    private var inbound: NIOAsyncChannelInboundStream<HTTPClientResponsePart>.AsyncIterator

    private init(
        address: HiveAddress,
        outbound: NIOAsyncChannelOutboundWriter<HTTPClientRequestPart>,
        inbound: NIOAsyncChannelInboundStream<HTTPClientResponsePart>.AsyncIterator
    ) {
        self.address = address
        self.outbound = outbound
        self.inbound = inbound
    }

    /// Connects, runs `body` with the open connection, and closes it when `body` returns or throws.
    public static func withConnection<Result>(
        to address: HiveAddress,
        pin: HiveKeyPin,
        on eventLoop: ScoutEventLoop,
        _ body: (PinnedHiveConnection) async throws -> Result
    ) async throws -> Result {
        // The handshake, and with it the pin check, finishes during the first request `body` makes.
        let refusal = PinRefusal()
        do {
            let channel = try await connect(to: address, pin: pin, refusal: refusal, on: eventLoop)
            return try await channel.executeThenClose { inbound, outbound in
                try await body(PinnedHiveConnection(address: address, outbound: outbound, inbound: inbound.makeAsyncIterator()))
            }
        } catch {
            if refusal.happened { throw HiveConnectionError.keyNotPinned }
            throw error
        }
    }

    /// Tries each address the host stands for, in turn, until one accepts the connection.
    private static func connect(
        to address: HiveAddress,
        pin: HiveKeyPin,
        refusal: PinRefusal,
        on eventLoop: ScoutEventLoop
    ) async throws -> Channel {
        let socketAddresses = try await eventLoop.runBlocking { try HostLookup.addresses(of: address) }
        var lastError: any Error = HostLookupError.noAddresses
        for socketAddress in socketAddresses {
            do {
                return try await connect(to: socketAddress, pin: pin, refusal: refusal, on: eventLoop)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func connect(
        to socketAddress: SocketAddress,
        pin: HiveKeyPin,
        refusal: PinRefusal,
        on eventLoop: ScoutEventLoop
    ) async throws -> Channel {
        let context = try NIOSSLContext(configuration: tlsConfiguration)
        return try await ClientBootstrap(group: eventLoop.loop)
            .connectTimeout(.seconds(10))
            .connect(to: socketAddress) { channel in
                channel.eventLoop.makeCompletedFuture {
                    let tls = try NIOSSLClientHandler(context: context, serverHostname: nil) { certificates, promise in
                        let leafKey = try? certificates.first?.extractPublicKey().toSPKIBytes()
                        if let leafKey, pin.matches(subjectPublicKeyInfo: leafKey) {
                            promise.succeed(.certificateVerified)
                        } else {
                            refusal.record()
                            promise.succeed(.failed)
                        }
                    }
                    try channel.pipeline.syncOperations.addHandler(tls)
                    try channel.pipeline.syncOperations.addHTTPClientHandlers()
                    return try Channel(wrappingChannelSynchronously: channel)
                }
            }
    }

    /// Asks Hive's health check, which keeps the connection from reaching Hive's idle timeout.
    public func checkHealth() async throws {
        let head = HTTPRequestHead(
            version: .http1_1,
            method: .GET,
            uri: "/health",
            headers: ["Host": address.hostHeader, "Connection": "keep-alive"]
        )
        try await outbound.write(contentsOf: [.head(head), .end(nil)])

        var status: HTTPResponseStatus?
        while let part = try await inbound.next(isolation: #isolation) {
            switch part {
            case .head(let response):
                status = response.status
            case .body:
                continue
            case .end:
                guard let status, status.code / 100 == 2 else { throw HiveConnectionError.unexpectedStatus(status?.code ?? 0) }
                return
            }
        }
        throw HiveConnectionError.closedByHive
    }
}
