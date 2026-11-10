import Foundation
import HiveKit
import NIOCore
import NIOPosix
import NIOSSL

/// Connects to mail servers over SwiftNIO, with TLS from NIOSSL checking certificates against the
/// system's trusted certificates and the host's name. There's no setting to skip the check.
struct NIOSMTPConnector: SMTPConnecting {
    static let connectTimeout = TimeAmount.seconds(30)
    /// RFC 5321 §4.5.3.2 suggests minutes for a few replies, such as after the message. Two covers
    /// providers that are slow without leaving an alert waiting long on one that's gone.
    static let replyTimeout = TimeAmount.minutes(2)

    func withConnection<Result: Sendable>(
        to server: SMTPServer,
        _ body: (any SMTPTransport) async throws -> Result
    ) async throws -> Result {
        let tls: NIOSSLContext
        do {
            var configuration = TLSConfiguration.makeClientConfiguration()
            configuration.certificateVerification = .fullVerification
            // Mail providers don't all offer TLS 1.3 yet.
            configuration.minimumTLSVersion = .tlsv12
            tls = try NIOSSLContext(configuration: configuration)
        } catch {
            throw EmailSendFailure(.secureConnectionFailed)
        }

        let channel: NIOAsyncChannel<ByteBuffer, ByteBuffer>
        do {
            channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .connectTimeout(Self.connectTimeout)
                .connect(host: server.host, port: server.port) { channel in
                    channel.eventLoop.makeCompletedFuture {
                        let pipeline = channel.pipeline.syncOperations
                        if server.security == .implicitTLS {
                            try pipeline.addHandler(NIOSSLClientHandler(context: tls, serverHostname: server.host))
                        }
                        try pipeline.addHandler(IdleStateHandler(readTimeout: Self.replyTimeout))
                        try pipeline.addHandler(QuietServerHandler())
                        return try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: channel)
                    }
                }
        } catch {
            throw EmailSendFailure(.couldNotConnect)
        }

        return try await channel.executeThenClose { inbound, outbound in
            let transport = NIOSMTPTransport(
                channel: channel.channel,
                inbound: inbound.makeAsyncIterator(),
                outbound: outbound,
                tls: tls,
                host: server.host
            )
            return try await body(transport)
        }
    }
}

private final class NIOSMTPTransport: SMTPTransport {
    private let channel: any Channel
    private var inbound: NIOAsyncChannelInboundStream<ByteBuffer>.AsyncIterator
    private let outbound: NIOAsyncChannelOutboundWriter<ByteBuffer>
    private let tls: NIOSSLContext
    private let host: String
    private var reader = SMTPReplyReader()

    init(
        channel: any Channel,
        inbound: NIOAsyncChannelInboundStream<ByteBuffer>.AsyncIterator,
        outbound: NIOAsyncChannelOutboundWriter<ByteBuffer>,
        tls: NIOSSLContext,
        host: String
    ) {
        self.channel = channel
        self.inbound = inbound
        self.outbound = outbound
        self.tls = tls
        self.host = host
    }

    func reply() async throws -> SMTPReply {
        while true {
            do {
                if let reply = try reader.next() { return reply }
            } catch {
                throw EmailSendFailure(.unexpectedReply)
            }
            let received: ByteBuffer?
            do {
                received = try await inbound.next(isolation: #isolation)
            } catch {
                throw Self.failure(for: error)
            }
            guard let received else { throw EmailSendFailure(.connectionClosed) }
            reader.append(received.readableBytesView)
        }
    }

    func send(_ bytes: [UInt8]) async throws {
        do {
            try await outbound.write(ByteBuffer(bytes: bytes))
        } catch {
            throw Self.failure(for: error)
        }
    }

    func startTLS() async throws {
        // Anything the server sent after agreeing to start TLS arrived unprotected, and may have been put
        // there by someone in between to be read as the server's answers once TLS is up.
        guard reader.isEmpty else { throw EmailSendFailure(.secureConnectionFailed) }
        do {
            try await channel.eventLoop.submit { [channel, tls, host] in
                try channel.pipeline.syncOperations.addHandler(NIOSSLClientHandler(context: tls, serverHostname: host), position: .first)
            }.get()
        } catch {
            throw EmailSendFailure(.secureConnectionFailed)
        }
    }

    private static func failure(for error: any Error) -> EmailSendFailure {
        switch error {
        case is NIOSSLError, is NIOSSLExtraError, is BoringSSLError: EmailSendFailure(.secureConnectionFailed)
        case is QuietServerError: EmailSendFailure(.timedOut)
        default: EmailSendFailure(.connectionClosed)
        }
    }
}

private struct QuietServerError: Error {}

/// Ends a connection whose server has sent nothing for `NIOSMTPConnector.replyTimeout`, including
/// during a TLS handshake, so a hung provider can't hold a send forever.
private final class QuietServerHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let idle = event as? IdleStateHandler.IdleStateEvent, idle == .read {
            context.fireErrorCaught(QuietServerError())
            context.close(promise: nil)
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }
}
