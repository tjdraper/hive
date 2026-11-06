import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct RsyncCommandTests {
    @Test("A pull deletes what the server no longer has, keeps owners, links to the previous snapshot, and times out")
    func pullOptions() {
        // Act
        let arguments = RsyncCommand.pull(linkingTo: URL(filePath: "/Volumes/Drive/Hive/s/j/old/files/site"))

        // Assert
        for option in ["--archive", "--delete", "--fake-super", "--numeric-ids", "--secluded-args", "--stats", "--timeout=300"] {
            #expect(arguments.contains(option))
        }
        #expect(arguments.contains("--link-dest=/Volumes/Drive/Hive/s/j/old/files/site/"))
    }

    @Test("A pull never changes files in place, which would change every snapshot sharing them")
    func neverInPlace() {
        // Act
        let arguments = RsyncCommand.pull(linkingTo: URL(filePath: "/tmp/old")) + RsyncCommand.list()

        // Assert
        for option in ["--inplace", "--append", "--append-verify", "--partial"] {
            #expect(!arguments.contains(option))
        }
        #expect(!arguments.contains { $0.hasPrefix("--link-dest") && !$0.hasSuffix("/") })
    }

    @Test("The first snapshot has nothing to link to")
    func noPrevious() {
        // Act
        let arguments = RsyncCommand.pull(linkingTo: nil)

        // Assert
        #expect(!arguments.contains { $0.hasPrefix("--link-dest") })
    }

    @Test("A source names what's in the directory, with an IPv6 address in brackets")
    func sources() {
        // Act, Assert
        #expect(RsyncCommand.remoteSource(host: "web.example.com", path: "/srv/site") == "web.example.com:/srv/site/")
        #expect(RsyncCommand.remoteSource(host: "fd7a:115c::1", path: "/srv/site") == "[fd7a:115c::1]:/srv/site/")
        #expect(RsyncCommand.remoteSource(host: "web.example.com", path: "/") == "web.example.com:/")
    }

    @Test("rsync runs ssh with every one of Hive's options, and never loosens host key checking")
    func remoteShell() async throws {
        // Arrange
        let target = SSHTarget(
            serverID: UUID(),
            connection: .init(host: "web.example.com", port: 2222, user: "backup"),
            hostKey: ConfigurationSamples.hostKey,
            key: SSHKeyPair()
        )

        // Act
        let shell = try await SSHSession.with(target, tools: SSHTools()) { session in
            try (session.remoteShell(), SSHCommand.options(for: target, in: session.directory))
        }

        // Assert
        #expect(shell.0 == (["/usr/bin/ssh"] + shell.1).joined(separator: " "))
        #expect(shell.0.contains("StrictHostKeyChecking=yes"))
        #expect(!shell.0.contains("StrictHostKeyChecking=no"))
        #expect(!shell.0.contains("web.example.com"))
    }

    @Test("A run folder whose path has a space is refused rather than split by rsync")
    func remoteShellRefusesSpaces() throws {
        // Arrange
        let temporary = try TemporaryDirectory()
        let parent = temporary.url.appending(path: "with space", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let target = SSHTarget(
            serverID: UUID(),
            connection: .init(host: "web.example.com", user: "backup"),
            hostKey: ConfigurationSamples.hostKey,
            key: SSHKeyPair()
        )
        let session = try SSHSession(target: target, directory: SSHRunDirectory.make(in: parent), tools: SSHTools())

        // Act, Assert
        #expect(throws: SSHSessionError.remoteShellNotPlain) { try session.remoteShell() }
    }
}
