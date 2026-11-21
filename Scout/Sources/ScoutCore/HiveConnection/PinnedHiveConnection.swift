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
    case answerTooLarge
    /// Hive took too long to answer, so the connection was closed.
    case timedOut
}

/// Hive's answer to one request.
public struct HiveAnswer: Equatable, Sendable {
    public let status: UInt
    public let body: [UInt8]

    public init(status: UInt, body: [UInt8]) {
        self.status = status
        self.body = body
    }
}

/// Requests to a Hive over a connection that's already open and pinned.
public protocol HiveRequesting {
    func send(_ method: String, _ path: String, body: [UInt8]?, token: String?) async throws -> HiveAnswer
}

/// Opens a pinned connection to one of Hive's addresses for a run of requests.
public protocol HiveConnecting: Sendable {
    func withConnection<Result>(
        to address: HiveAddress,
        pin: HiveKeyPin,
        _ body: (any HiveRequesting) async throws -> Result
    ) async throws -> Result
}

public struct PinnedHiveConnector: HiveConnecting {
    let eventLoop: ScoutEventLoop

    public init(eventLoop: ScoutEventLoop = .shared) {
        self.eventLoop = eventLoop
    }

    public func withConnection<Result>(
        to address: HiveAddress,
        pin: HiveKeyPin,
        _ body: (any HiveRequesting) async throws -> Result
    ) async throws -> Result {
        try await PinnedHiveConnection.withConnection(to: address, pin: pin, on: eventLoop) { try await body($0) }
    }
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

    /// Set by the pin check or a request's timer, so what closed the connection can be told apart
    /// from the failure it causes.
    private final class Occurrence: Sendable {
        private let occurred = Mutex(false)

        var happened: Bool {
            occurred.withLock { $0 }
        }

        func record() {
            occurred.withLock { $0 = true }
        }
    }

    /// Covers the TLS handshake, which finishes during the first request. A Hive that accepts a
    /// connection and then stops answering counts as unreachable after it.
    static let requestTimeout: TimeAmount = .seconds(30)

    /// Far more than any answer Scout reads, so a Hive that misbehaves can't fill Scout's memory.
    private static let largestAnswer = 64 * 1024

    private let address: HiveAddress
    private let timeout: TimeAmount
    private let channel: any NIOCore.Channel
    private let outbound: NIOAsyncChannelOutboundWriter<HTTPClientRequestPart>
    private var inbound: NIOAsyncChannelInboundStream<HTTPClientResponsePart>.AsyncIterator

    private init(
        address: HiveAddress,
        requestTimeout: TimeAmount,
        channel: any NIOCore.Channel,
        outbound: NIOAsyncChannelOutboundWriter<HTTPClientRequestPart>,
        inbound: NIOAsyncChannelInboundStream<HTTPClientResponsePart>.AsyncIterator
    ) {
        self.address = address
        timeout = requestTimeout
        self.channel = channel
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
        try await withChannel(to: address, requestTimeout: Self.requestTimeout, body) { refusal in
            try await connect(to: address, pin: pin, refusal: refusal, on: eventLoop)
        }
    }

    /// Over a socket that's already connected, so tests can stand in for Hive without listening on a port.
    static func withConnection<Result>(
        connectedSocket socket: NIOBSDSocket.Handle,
        pin: HiveKeyPin,
        on eventLoop: ScoutEventLoop,
        requestTimeout: TimeAmount,
        _ body: (PinnedHiveConnection) async throws -> Result
    ) async throws -> Result {
        let address = HiveAddress(host: "localhost", port: 1)
        return try await withChannel(to: address, requestTimeout: requestTimeout, body) { refusal in
            let context = try NIOSSLContext(configuration: tlsConfiguration)
            return try await ClientBootstrap(group: eventLoop.loop).withConnectedSocket(socket) { channel in
                channel.eventLoop.makeCompletedFuture { try pipeline(on: channel, context: context, pin: pin, refusal: refusal) }
            }
        }
    }

    private static func withChannel<Result>(
        to address: HiveAddress,
        requestTimeout: TimeAmount,
        _ body: (PinnedHiveConnection) async throws -> Result,
        connecting: (Occurrence) async throws -> Channel
    ) async throws -> Result {
        // The handshake, and with it the pin check, finishes during the first request `body` makes.
        let refusal = Occurrence()
        do {
            let channel = try await connecting(refusal)
            return try await channel.executeThenClose { inbound, outbound in
                try await body(PinnedHiveConnection(
                    address: address,
                    requestTimeout: requestTimeout,
                    channel: channel.channel,
                    outbound: outbound,
                    inbound: inbound.makeAsyncIterator()
                ))
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
        refusal: Occurrence,
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
        refusal: Occurrence,
        on eventLoop: ScoutEventLoop
    ) async throws -> Channel {
        let context = try NIOSSLContext(configuration: tlsConfiguration)
        return try await ClientBootstrap(group: eventLoop.loop)
            .connectTimeout(.seconds(10))
            .connect(to: socketAddress) { channel in
                channel.eventLoop.makeCompletedFuture { try pipeline(on: channel, context: context, pin: pin, refusal: refusal) }
            }
    }

    private static func pipeline(
        on channel: any NIOCore.Channel,
        context: NIOSSLContext,
        pin: HiveKeyPin,
        refusal: Occurrence
    ) throws -> Channel {
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

    /// Asks Hive's health check, which keeps the connection from reaching Hive's idle timeout.
    public func checkHealth() async throws {
        let answer = try await send("GET", "/health")
        guard answer.status / 100 == 2 else { throw HiveConnectionError.unexpectedStatus(answer.status) }
    }

    /// Sends a request and reads Hive's whole answer. A body, even an empty one, is sent as JSON.
    /// Closes the connection when Hive takes longer than its timeout.
    public func send(_ method: String, _ path: String, body: [UInt8]? = nil, token: String? = nil) async throws -> HiveAnswer {
        let timedOut = Occurrence()
        // Closing the channel is what ends a write or read that's waiting on Hive.
        let timer = channel.eventLoop.scheduleTask(in: timeout) { [channel] in
            timedOut.record()
            channel.close(promise: nil)
        }
        defer { timer.cancel() }
        do {
            return try await exchange(method, path, body: body, token: token)
        } catch {
            if timedOut.happened { throw HiveConnectionError.timedOut }
            throw error
        }
    }

    private func exchange(_ method: String, _ path: String, body: [UInt8]?, token: String?) async throws -> HiveAnswer {
        var headers: HTTPHeaders = ["Host": address.hostHeader, "Connection": "keep-alive"]
        if let token { headers.add(name: "Authorization", value: "Bearer \(token)") }
        if let body {
            headers.add(name: "Content-Type", value: "application/json")
            headers.add(name: "Content-Length", value: String(body.count))
        }
        let head = HTTPRequestHead(version: .http1_1, method: HTTPMethod(rawValue: method), uri: path, headers: headers)
        var parts: [HTTPClientRequestPart] = [.head(head)]
        if let body, !body.isEmpty { parts.append(.body(.byteBuffer(ByteBuffer(bytes: body)))) }
        parts.append(.end(nil))
        try await outbound.write(contentsOf: parts)

        var status: UInt?
        var received: [UInt8] = []
        while let part = try await inbound.next(isolation: #isolation) {
            switch part {
            case .head(let response):
                status = response.status.code
            case .body(let buffer):
                received += buffer.readableBytesView
                guard received.count <= Self.largestAnswer else { throw HiveConnectionError.answerTooLarge }
            case .end:
                guard let status else { throw HiveConnectionError.closedByHive }
                return HiveAnswer(status: status, body: received)
            }
        }
        throw HiveConnectionError.closedByHive
    }
}

extension PinnedHiveConnection: HiveRequesting {}
