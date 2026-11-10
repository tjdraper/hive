import CryptoKit
@testable import HiveCore
import NIOCore
import NIOEmbedded
import NIOSSL
import Testing

/// Handshakes between two in-memory channels, so no port is opened.
struct TLSHandshakeTests {
    private let key = P256.Signing.PrivateKey()
    private let identity: TLSIdentity

    init() throws {
        let temporary = try TemporaryDirectory()
        let certificate = try IdentityCertificateStore(directory: temporary.url).loadOrIssue(for: key)
        identity = TLSIdentity(key: key, certificate: certificate)
    }

    @Test("A client completes a handshake signed by the identity key, and sees that key")
    func handshakeSignedByIdentityKey() throws {
        // Arrange
        let client = try makeClient(maximumVersion: nil)
        let server = try makeServer()

        // Act
        try handshake(client: client, server: server)

        // Assert
        let handler = try client.pipeline.syncOperations.handler(type: NIOSSLClientHandler.self)
        let peerKey = try #require(handler.peerCertificate).extractPublicKey()
        #expect(try peerKey.toSPKIBytes() == Array(key.publicKey.derRepresentation))
    }

    @Test("A client limited to TLS 1.2 is refused")
    func refusesTLS12() throws {
        // Arrange
        let client = try makeClient(maximumVersion: .tlsv12)
        let server = try makeServer()

        // Act, Assert
        #expect(throws: (any Error).self) { try handshake(client: client, server: server) }
    }

    @Test("A closing connection waits at most a second for the client, so it can't hold up Hive stopping")
    func shortShutdown() throws {
        // Act
        let configuration = try identity.serverConfiguration()

        // Assert
        #expect(configuration.shutdownTimeout <= .seconds(1))
    }

    private func makeServer() throws -> EmbeddedChannel {
        let context = try NIOSSLContext(configuration: identity.serverConfiguration())
        let channel = EmbeddedChannel(handler: NIOSSLServerHandler(context: context))
        try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 4483)).wait()
        return channel
    }

    /// Leaves the chain and hostname unchecked, as Beekeeper does, so the test checks the key itself. The
    /// handshake still checks the server's signature.
    private func makeClient(maximumVersion: TLSVersion?) throws -> EmbeddedChannel {
        var configuration = TLSConfiguration.makeClientConfiguration()
        configuration.certificateVerification = .noHostnameVerification
        configuration.maximumTLSVersion = maximumVersion

        let context = try NIOSSLContext(configuration: configuration)
        let handler = try NIOSSLClientHandler(context: context, serverHostname: nil) { _, promise in
            promise.succeed(.certificateVerified)
        }
        let channel = EmbeddedChannel(handler: handler)
        try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 4483)).wait()
        return channel
    }

    /// Passes bytes back and forth until neither side has more to send.
    private func handshake(client: EmbeddedChannel, server: EmbeddedChannel) throws {
        var moved = true
        while moved {
            moved = false
            client.embeddedEventLoop.run()
            server.embeddedEventLoop.run()
            while let bytes = try client.readOutbound(as: ByteBuffer.self) {
                try server.writeInbound(bytes)
                moved = true
            }
            while let bytes = try server.readOutbound(as: ByteBuffer.self) {
                try client.writeInbound(bytes)
                moved = true
            }
        }
        try client.throwIfErrorCaught()
        try server.throwIfErrorCaught()
    }
}
