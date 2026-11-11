import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

struct SSHKeyRotationTests {
    static let otherKeyLine = "ssh-ed25519 \(SSHKeyPair().publicKey.line.split(separator: " ")[1]) someone@laptop"
    static let options = #"restrict,from="100.64.0.7""#

    private struct RotationFixture {
        let api: APIFixture
        let server: Server
        let keyServer: FakeKeyServer
        let old: OpenSSHPublicKey
    }

    /// A fixture whose one server accepts Hive's key from the Mac's Tailscale address, beside someone else's key.
    private static func rotationFixture() async throws -> RotationFixture {
        let fixture = try APIFixture()
        let server = try await fixture.addServer()
        try await fixture.confirmHostKey(of: server)
        let old = try #require(try ServerSSHKeyStore(database: fixture.signIn.database).publicKey(forServer: server.id))
        let keyServer = try FakeKeyServer(lines: [
            "# keys for backups",
            otherKeyLine,
            "\(options) \(old.line) Hive Test Hive",
        ])
        return RotationFixture(api: fixture, server: server, keyServer: keyServer, old: old)
    }

    private static func rotate(_ fixture: APIFixture, on keyServer: FakeKeyServer) async throws -> SSHKeyRotationState {
        let workflow = SSHKeyRotationWorkflow(
            database: fixture.signIn.database,
            sealer: fixture.sealer,
            ssh: keyServer,
            runs: fixture.api.runs,
            settings: fixture.settings,
            now: { [clock = fixture.signIn.clock] in clock.now }
        )
        _ = try await workflow.start(isConfirmed: true, by: fixture.signIn.device.id)
        await workflow.waitUntilFinished()
        return await workflow.state()
    }

    @Test("Rotating leaves the server with only the new key, limited as the old one was, and Hive using it")
    func rotates() async throws {
        // Arrange
        let setUp = try await Self.rotationFixture()
        let (fixture, server, keyServer, old) = (setUp.api, setUp.server, setUp.keyServer, setUp.old)

        // Act
        let state = try await Self.rotate(fixture, on: keyServer)

        // Assert
        let new = try #require(try ServerSSHKeyStore(database: fixture.signIn.database).publicKey(forServer: server.id))
        #expect(new != old)
        let result = SSHKeyRotationResult(serverID: server.id, serverName: server.name, outcome: .rotated(fingerprint: new.fingerprint))
        #expect(state.results == [result])
        #expect(state.finishedAt != nil)
        #expect(try keyServer.lines == ["# keys for backups", Self.otherKeyLine, "\(Self.options) \(new.line) Hive Test Hive"])
        #expect(try fixture.auditEvents().first == .server(
            serverID: server.id,
            serverName: server.name,
            change: .sshKeyRotated(old: old.fingerprint, new: new.fingerprint)
        ))
        // The old key was removed over a connection made with the new one.
        #expect(keyServer.commands.last?.key == new)
    }

    @Test("A server that turns the new key down keeps its old key, and Hive goes on using it")
    func newKeyRefused() async throws {
        // Arrange
        let setUp = try await Self.rotationFixture()
        let (fixture, server, keyServer, old) = (setUp.api, setUp.server, setUp.keyServer, setUp.old)
        let before = try keyServer.contents
        let auditBefore = try fixture.auditEvents()
        keyServer.acceptOnly([old])

        // Act
        let state = try await Self.rotate(fixture, on: keyServer)

        // Assert
        #expect(state.results.map(\.outcome) == [.failed(.newKeyRefused(.loginRefused))])
        #expect(try keyServer.contents == before)
        #expect(try ServerSSHKeyStore(database: fixture.signIn.database).publicKey(forServer: server.id) == old)
        #expect(try fixture.auditEvents() == auditBefore)
    }

    @Test("A server whose authorized_keys doesn't hold the old key is left as it is")
    func oldKeyNotFound() async throws {
        // Arrange
        let setUp = try await Self.rotationFixture()
        let (fixture, server, keyServer, old) = (setUp.api, setUp.server, setUp.keyServer, setUp.old)
        try keyServer.write(Self.otherKeyLine + "\n")
        keyServer.alsoAccept(old)

        // Act
        let state = try await Self.rotate(fixture, on: keyServer)

        // Assert
        #expect(state.results.map(\.outcome) == [.failed(.oldKeyNotFound)])
        #expect(try keyServer.lines == [Self.otherKeyLine])
        #expect(try ServerSSHKeyStore(database: fixture.signIn.database).publicKey(forServer: server.id) == old)
    }

    @Test("A server Hive can't reach keeps its old key")
    func unreachable() async throws {
        // Arrange
        let setUp = try await Self.rotationFixture()
        let (fixture, server, keyServer, old) = (setUp.api, setUp.server, setUp.keyServer, setUp.old)
        let before = try keyServer.contents
        keyServer.acceptOnly([])

        // Act
        let state = try await Self.rotate(fixture, on: keyServer)

        // Assert
        #expect(state.results.map(\.outcome) == [.failed(.connection(.loginRefused))])
        #expect(try keyServer.contents == before)
        #expect(try ServerSSHKeyStore(database: fixture.signIn.database).publicKey(forServer: server.id) == old)
    }

    @Test("When the old key's line can't be removed, Hive uses the new key and says the old one is still there")
    func oldKeyLeft() async throws {
        // Arrange
        let setUp = try await Self.rotationFixture()
        let (fixture, server, keyServer, old) = (setUp.api, setUp.server, setUp.keyServer, setUp.old)
        keyServer.failRemoval()

        // Act
        let state = try await Self.rotate(fixture, on: keyServer)

        // Assert
        let new = try #require(try ServerSSHKeyStore(database: fixture.signIn.database).publicKey(forServer: server.id))
        #expect(state.results.map(\.outcome) == [.oldKeyLeft(fingerprint: new.fingerprint)])
        #expect(try keyServer.lines == [
            "# keys for backups",
            Self.otherKeyLine,
            "\(Self.options) \(old.line) Hive Test Hive",
            "\(Self.options) \(new.line) Hive Test Hive",
        ])
    }

    @Test("A server that isn't set up yet has nothing to rotate")
    func notSetUp() async throws {
        // Arrange
        let fixture = try APIFixture()
        let server = try await fixture.addServer()
        let keyServer = try FakeKeyServer(lines: [])

        // Act
        let state = try await Self.rotate(fixture, on: keyServer)

        // Assert
        #expect(state.results == [SSHKeyRotationResult(serverID: server.id, serverName: server.name, outcome: .notSetUp)])
        #expect(keyServer.commands.isEmpty)
    }

    @Test("A run queued while rotation holds the queue starts only once it's done")
    func holdsTheQueue() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        let (runs, jobID, deviceID) = (fixture.runs, fixture.job.id, fixture.api.signIn.device.id)

        // Act
        let ranWhileHeld = await runs.whileHeld {
            let queued = try? await runs.runNow(jobID: jobID, by: deviceID)
            try? await Task.sleep(for: .milliseconds(200))
            let current = await runs.current()
            return queued != .queued || current != nil
        }
        await runs.waitUntilIdle()

        // Assert
        #expect(!ranWhileHeld)
        #expect(try fixture.snapshots().count == 1)
    }

    @Test("A rotation started through the API answers at once and finishes in the background")
    func throughTheAPI() async throws {
        // Arrange
        let fixture = try APIFixture()

        // Act
        let started = try await fixture.sendConfirmed(.post, HiveEndpoint.sshKeyRotation)
        await fixture.api.sshKeyRotation.waitUntilFinished()
        let state = try await fixture.send(.get, HiveEndpoint.sshKeyRotation).decoded(as: SSHKeyRotationState.self)

        // Assert
        #expect(started.status == .accepted)
        #expect(try started.decoded(as: SSHKeyRotationState.self).isRunning)
        #expect(state.startedAt != nil)
        #expect(!state.isRunning)
    }
}

struct AuthorizedKeysTests {
    @Test("Lines with options, quoted spaces, comments or none are read, and other lines skipped")
    func readsLines() throws {
        let key = SSHKeyPair().publicKey
        let lines = [
            "\(key.line)",
            "restrict \(key.line) Hive",
            #"command="echo hi there",restrict \#(key.line) with a comment"#,
            "  # \(key.line)",
            "",
            "not a key line",
        ]

        let entries = lines.compactMap(AuthorizedKeysFile.entry)

        #expect(entries.map(\.options) == [nil, "restrict", #"command="echo hi there",restrict"#])
        #expect(entries.allSatisfy { $0.key == key })
    }

    @Test("Adding a line starts it on a line of its own, and never adds it twice")
    func addsOnce() async throws {
        // Arrange
        let key = SSHKeyPair().publicKey
        let server = try FakeKeyServer(lines: [])
        try server.write("ssh-ed25519 AAAA first")
        let target = Self.target()
        server.acceptOnly([target.key.publicKey])
        let line = "restrict \(key.line) Hive"

        // Act
        let first = try await server.run(AuthorizedKeysScript.add(line), on: target)
        let second = try await server.run(AuthorizedKeysScript.add(line), on: target)

        // Assert
        #expect(first.status == 0)
        #expect(second.status == 0)
        #expect(try server.contents == "ssh-ed25519 AAAA first\n\(line)\n")
    }

    @Test("Removing takes out exactly the lines named, and nothing unless the kept line is there")
    func removesExactly() async throws {
        // Arrange
        let target = Self.target()
        let old = "restrict ssh-ed25519 AAAAold Hive"
        let kept = "restrict ssh-ed25519 AAAAnew Hive"
        let lookalike = "restrict ssh-ed25519 AAAAold Hive and more"
        let server = try FakeKeyServer(lines: [old, lookalike, kept])
        server.acceptOnly([target.key.publicKey])
        let withoutKept = try FakeKeyServer(lines: [old])
        withoutKept.acceptOnly([target.key.publicKey])

        // Act
        let removed = try await server.run(AuthorizedKeysScript.remove([old], keeping: kept), on: target)
        let refused = try await withoutKept.run(AuthorizedKeysScript.remove([old], keeping: kept), on: target)

        // Assert
        #expect(removed.status == 0)
        #expect(try server.lines == [lookalike, kept])
        #expect(refused.status != 0)
        #expect(try withoutKept.lines == [old])
        let sshFolder = server.home.url.appending(path: ".ssh").fileSystemPath
        #expect(try FileManager.default.contentsOfDirectory(atPath: sshFolder) == ["authorized_keys"])
    }

    private static func target() -> SSHTarget {
        SSHTarget(serverID: UUID(), connection: ServerConnection(host: "h", user: "u"), hostKey: SSHKeyPair().publicKey, key: SSHKeyPair())
    }
}
