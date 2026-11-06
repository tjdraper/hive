import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct HostKeyScanParserTests {
    private static let ed25519 = SSHKeyPair().publicKey

    /// An ECDSA key as OpenSSH writes it. Only its type and blob matter here.
    private static let ecdsa = OpenSSHPublicKey(
        keyType: "ecdsa-sha2-nistp256",
        blob: SSHWireFormat.string("ecdsa-sha2-nistp256")
            + SSHWireFormat.string("nistp256")
            + SSHWireFormat.string(Data(repeating: 4, count: 65))
    )

    @Test("The Ed25519 key is chosen over others, whatever order they came in")
    func prefersEd25519() {
        // Arrange
        let output = """
        # [127.0.0.1]:2222 SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.5
        [127.0.0.1]:2222 \(Self.ecdsa.line)
        # [127.0.0.1]:2222 SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.5
        [127.0.0.1]:2222 \(Self.ed25519.line)

        """

        // Act
        let outcome = HostKeyScanParser.outcome(from: output)

        // Assert
        #expect(outcome == .found(Self.ed25519))
    }

    @Test("Another type is used when the server has no Ed25519 key")
    func fallsBackToOtherTypes() {
        // Act
        let outcome = HostKeyScanParser.outcome(from: "web.example.com \(Self.ecdsa.line)\n")

        // Assert
        #expect(outcome == .found(Self.ecdsa))
    }

    @Test("Nothing found reads as the server not answering")
    func nothingFound() {
        // Act
        let outcome = HostKeyScanParser.outcome(from: "")

        // Assert
        #expect(outcome == .failed(.unreachable))
    }

    @Test("Keys only of types Hive doesn't record, or that don't read, are a failure")
    func unusableKeys() {
        // Arrange
        let other = OpenSSHPublicKey(keyType: "ssh-dss", blob: SSHWireFormat.string("ssh-dss") + Data(repeating: 1, count: 20))

        // Act
        let outcome = HostKeyScanParser.outcome(from: "web.example.com \(other.line)\nweb.example.com ssh-ed25519 AAAA\n")

        // Assert
        #expect(outcome == .failed(.failed))
    }
}
