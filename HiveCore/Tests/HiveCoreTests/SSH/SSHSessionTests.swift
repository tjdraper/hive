import Foundation
@testable import HiveCore
import HiveKit
import Testing

/// Runs the Mac's own `ssh-agent` and `ssh-add` against a socket in a temporary folder. No `ssh`, and no server.
struct SSHSessionTests {
    private static let tools = SSHTools()

    private static func listedKeys(socket: URL) async throws -> ChildProcess.Result {
        try await ChildProcess(
            executableURL: tools.add,
            arguments: ["-L"],
            environment: SSHTools.environment(adding: ["SSH_AUTH_SOCK": socket.fileSystemPath])
        ).run()
    }

    @Test("The run folder is open only to its owner, and is gone once removed")
    func runDirectoryIsPrivate() throws {
        // Arrange
        let directory = try SSHRunDirectory.make()

        // Act
        let mode = try permissions(of: directory.url.fileSystemPath)
        directory.remove()

        // Assert
        #expect(mode == 0o700)
        #expect(!FileManager.default.fileExists(atPath: directory.url.fileSystemPath))
        #expect(directory.agentSocket.fileSystemPath.utf8.count < 104)
    }

    @Test("The agent holds exactly Hive's key, and forgets it when stopped")
    func agentHoldsKey() async throws {
        // Arrange
        let directory = try SSHRunDirectory.make()
        defer { directory.remove() }
        let key = SSHKeyPair()
        let agent = try await SSHAgent.start(socket: directory.agentSocket, tools: Self.tools)

        // Act
        try await agent.add(key, comment: "test")
        let listed = try await Self.listedKeys(socket: directory.agentSocket)
        agent.stop()
        try await Task.sleep(for: .milliseconds(200))
        let afterStop = try await Self.listedKeys(socket: directory.agentSocket)

        // Assert
        let lines = (String(bytes: listed.standardOutput, encoding: .utf8) ?? "").split(separator: "\n")
        #expect(lines.map { OpenSSHPublicKey(line: String($0)) } == [key.publicKey])
        #expect(afterStop.status != 0)
    }

    @Test("A session writes the confirmed host key and Hive's public key, and removes its folder afterward")
    func sessionCleansUp() async throws {
        // Arrange
        let target = SSHTarget(
            serverID: UUID(),
            connection: .init(host: "web.example.com", user: "root"),
            hostKey: ConfigurationSamples.hostKey,
            key: SSHKeyPair()
        )

        // Act
        let (folder, knownHosts, identity) = try await SSHSession.with(target, tools: Self.tools) { session in
            try (
                session.directory.url,
                String(contentsOf: session.directory.knownHosts, encoding: .utf8),
                String(contentsOf: session.directory.identity, encoding: .utf8)
            )
        }

        // Assert
        #expect(knownHosts == KnownHostsFile.contents(for: target))
        #expect(identity == target.key.publicKey.line + "\n")
        #expect(!FileManager.default.fileExists(atPath: folder.fileSystemPath))
    }
}
