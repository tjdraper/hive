import CryptoKit
import Foundation
@testable import HiveCore
import Testing

/// Checked against the Mac's own `ssh-keygen`, which reads keys and reaches no server.
struct SSHKeyPairTests {
    private static func sshKeygen(_ arguments: [String]) async throws -> String {
        let result = try await ChildProcess(
            executableURL: URL(filePath: "/usr/bin/ssh-keygen"),
            arguments: arguments,
            environment: SSHTools.environment()
        ).run()
        #expect(result.status == 0, "\(String(bytes: result.standardError, encoding: .utf8) ?? "")")
        return (String(bytes: result.standardOutput, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("ssh-keygen reads the private key file and finds the same public key")
    func privateKeyFileIsValid() async throws {
        // Arrange
        let temporary = try TemporaryDirectory()
        let key = SSHKeyPair()
        let file = temporary.url.appending(path: "key")
        try key.privateKeyFile(comment: "test").write(to: file)
        chmod(file.fileSystemPath, 0o600)

        // Act
        let derived = try await Self.sshKeygen(["-y", "-f", file.fileSystemPath])

        // Assert
        #expect(OpenSSHPublicKey(line: derived) == key.publicKey)
    }

    @Test("The fingerprint is the one ssh-keygen shows")
    func fingerprintMatchesSSHKeygen() async throws {
        // Arrange
        let temporary = try TemporaryDirectory()
        let key = SSHKeyPair()
        let file = temporary.url.appending(path: "key.pub")
        try Data((key.publicKey.line + "\n").utf8).write(to: file)

        // Act
        let listed = try await Self.sshKeygen(["-l", "-E", "sha256", "-f", file.fileSystemPath])

        // Assert
        #expect(listed.split(separator: " ")[1] == Substring(key.publicKey.fingerprint))
    }

    @Test("The key comes back the same from its seed")
    func roundTripsThroughSeed() throws {
        // Arrange
        let key = SSHKeyPair()

        // Act
        let restored = try SSHKeyPair(seed: key.seed)

        // Assert
        #expect(restored.publicKey == key.publicKey)
        #expect(key.seed.count == 32)
    }

    @Test("A public key line whose blob names another type is refused")
    func refusesMismatchedType() throws {
        // Arrange
        let key = SSHKeyPair().publicKey
        let blob = key.blob.base64EncodedString()

        // Act
        let parsed = OpenSSHPublicKey(line: "ssh-rsa \(blob)")

        // Assert
        #expect(parsed == nil)
        #expect(OpenSSHPublicKey(line: "\(key.line) a comment") == key)
        #expect(OpenSSHPublicKey(line: "ssh-ed25519 not-base64") == nil)
        #expect(OpenSSHPublicKey(line: "ssh-ed25519") == nil)
    }

    @Test("The authorized_keys line is restricted, and limited to the given addresses")
    func authorizedKeysLine() {
        // Arrange
        let key = SSHKeyPair().publicKey

        // Act
        let open = AuthorizedKeysLine.line(for: key, comment: "Hive Studio")
        let limited = AuthorizedKeysLine.line(for: key, comment: "Hive Studio", from: ["100.64.0.7", "fd7a:115c:a1e0::7"])

        // Assert
        #expect(open == "restrict \(key.line) Hive Studio")
        #expect(limited == "restrict,from=\"100.64.0.7,fd7a:115c:a1e0::7\" \(key.line) Hive Studio")
    }
}
