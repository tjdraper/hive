import NIOCore
import NIOSSL
import SwiftASN1
import X509

/// How Hive proves who it is to every connection.
public struct TLSIdentity {
    let key: any IdentitySigningKey
    let certificate: Certificate

    public init(key: any IdentitySigningKey, certificate: Certificate) {
        self.key = key
        self.certificate = certificate
    }

    /// TLS 1.3 only. Every Beekeeper platform supports it, and it leaves out the older key exchanges.
    public func serverConfiguration() throws -> TLSConfiguration {
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        var configuration = TLSConfiguration.makeServerConfiguration(
            certificateChain: [.certificate(try NIOSSLCertificate(bytes: serializer.serializedBytes, format: .der))],
            privateKey: .privateKey(NIOSSLPrivateKey(customPrivateKey: IdentityTLSKey(key: key)))
        )
        configuration.minimumTLSVersion = .tlsv13
        // How long a closing connection waits for the client's close_notify. URLSession keeps a finished
        // connection open without sending one, and with the default 5 seconds a connection open when
        // Hive stops held it up until launchd killed it, cutting short a run's cleanup.
        configuration.shutdownTimeout = .seconds(1)
        return configuration
    }
}
