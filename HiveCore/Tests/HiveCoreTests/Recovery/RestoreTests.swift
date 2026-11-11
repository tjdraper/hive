import CryptoKit
import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

struct RestoreTests {
    @Test("Restoring gives the same Hive ID, configuration and secrets, sealed for the new storage key")
    func restoresEverything() async throws {
        // Arrange
        let old = try APIFixture()
        _ = try await old.addEverything()
        let key = RecoveryKey()
        try await old.saveRecoveryKey(key)
        let file = try Data(contentsOf: old.recoveryFile)
        let new = try APIFixture()

        // Act
        let outcome = try new.restore(file, key: key)

        // Assert
        let oldID = try old.signIn.database.hiveID()
        #expect(outcome.hiveID == oldID)
        #expect(outcome.port == APIFixture.defaultPort)
        #expect(try new.signIn.database.hiveID() == oldID)
        #expect(try new.openedContents() == old.openedContents())
        #expect(try new.recoveryKeyState().publicKey == key.publicKey.rawRepresentation)
        #expect(new.restart.isRequested)

        let sealed = try new.sealedContents()
        let sshKey = try #require(sealed.servers.first?.sshKey?.seed)
        let password = try #require(sealed.servers.first?.jobs.first?.databases.first?.password)
        let smtpPassword = try #require(sealed.email?.password)
        for secret in [sshKey, password, smtpPassword] {
            #expect(throws: SecretSealingError.couldNotOpen) { try old.sealer.open(SealedSecret(data: secret)) }
            #expect(throws: Never.self) { try new.sealer.open(SealedSecret(data: secret)) }
        }
        #expect(try new.auditEvents().first == .restoredFromRecoveryFile(writtenAt: old.signIn.clock.now, serverCount: 1, jobCount: 1))
    }

    @Test("A restored Hive listens on the old Hive's port, and says so")
    func keepsPort() async throws {
        // Arrange
        let old = try APIFixture()
        _ = try await old.addEverything()
        let settings = HiveSettings(name: "Studio Hive", networkAccess: .thisMacOnly, port: 5_000)
        let changed = try await old.send(.put, HiveEndpoint.settings, json: settings)
        #expect(changed.status == .ok)
        let key = RecoveryKey()
        try await old.saveRecoveryKey(key)
        let new = try APIFixture()

        // Act
        let outcome = try new.restore(Data(contentsOf: old.recoveryFile), key: key)

        // Assert
        #expect(outcome.port == 5_000)
        #expect(outcome.hiveName == "Studio Hive")
        #expect(try new.settings.settings().port == 5_000)
    }

    @Test("A restored Hive writes its recovery files with the same recovery key")
    func keepsRecoveryKey() async throws {
        // Arrange
        let old = try APIFixture()
        _ = try await old.addEverything()
        let key = RecoveryKey()
        try await old.saveRecoveryKey(key)
        let new = try APIFixture()
        _ = try new.restore(Data(contentsOf: old.recoveryFile), key: key)

        // Act
        let wrote = await new.api.recoveryFiles.writeIfDue()

        // Assert
        #expect(wrote)
        #expect(try new.openRecoveryFile(with: key).hive.id == old.signIn.database.hiveID())
    }

    @Test("A restore from anywhere but the Hive's own Mac is refused and changes nothing")
    func refusesFromElsewhere() async throws {
        // Arrange
        let old = try APIFixture()
        _ = try await old.addEverything()
        let key = RecoveryKey()
        try await old.saveRecoveryKey(key)
        let new = try APIFixture()
        let before = try new.snapshotOfState()
        let request = RestoreRequest(file: try Data(contentsOf: old.recoveryFile), recoveryKeyCode: key.code)

        // Act
        let answer = try await new.send(.post, HiveEndpoint.restore, json: request)

        // Assert
        #expect(answer.status == .unprocessableContent)
        #expect(try answer.decoded(as: RestoreRefusal.self).problem == .notOnThisMac)
        #expect(try new.snapshotOfState() == before)
    }

    @Test("Only loopback connections count as the Hive's own Mac")
    func loopbackOnly() throws {
        #expect(RestoreRoutes.isLoopback(try SocketAddress(ipAddress: "127.0.0.1", port: 4483)))
        #expect(RestoreRoutes.isLoopback(try SocketAddress(ipAddress: "::1", port: 4483)))
        #expect(RestoreRoutes.isLoopback(try SocketAddress(ipAddress: "::ffff:127.0.0.1", port: 4483)))
        #expect(!RestoreRoutes.isLoopback(try SocketAddress(ipAddress: "100.64.0.7", port: 4483)))
        #expect(!RestoreRoutes.isLoopback(try SocketAddress(ipAddress: "192.168.1.20", port: 4483)))
        #expect(!RestoreRoutes.isLoopback(try SocketAddress(ipAddress: "fd7a:115c:a1e0::1", port: 4483)))
        #expect(!RestoreRoutes.isLoopback(nil))
    }

    @Test("A restore with a mistyped key, another key, or a changed or foreign file is refused and changes nothing")
    func refusesBadFileOrKey() async throws {
        // Arrange
        let old = try APIFixture()
        _ = try await old.addEverything()
        let key = RecoveryKey()
        try await old.saveRecoveryKey(key)
        let file = try Data(contentsOf: old.recoveryFile)
        var changed = file
        changed[changed.count - 1] ^= 0x01
        var mistyped = Array(key.code)
        mistyped[0] = mistyped[0] == "A" ? "B" : "A"
        let cases: [(request: RestoreRequest, problem: RestoreProblem)] = [
            (RestoreRequest(file: file, recoveryKeyCode: String(mistyped)), .mistypedKey),
            (RestoreRequest(file: file, recoveryKeyCode: RecoveryKey().code), .otherKey),
            (RestoreRequest(file: changed, recoveryKeyCode: key.code), .couldNotOpen),
            (RestoreRequest(file: Data("not a recovery file".utf8), recoveryKeyCode: key.code), .notARecoveryFile),
        ]
        let new = try APIFixture()
        let before = try new.snapshotOfState()

        for (request, problem) in cases {
            // Act and Assert
            #expect(throws: RestoreError.refused(problem)) {
                try new.api.restore.restore(request, isFromThisMac: true, by: new.signIn.device.id)
            }
        }
        #expect(try new.snapshotOfState() == before)
    }

    @Test("A Hive with any configuration can't be restored over")
    func refusesConfiguredHive() async throws {
        // Arrange
        let old = try APIFixture()
        _ = try await old.addEverything()
        let key = RecoveryKey()
        try await old.saveRecoveryKey(key)
        let file = try Data(contentsOf: old.recoveryFile)
        let setUps: [(String, @Sendable (APIFixture) async throws -> Void)] = [
            ("a server", { _ = try await $0.addServer() }),
            ("a recovery key", { try await $0.saveRecoveryKey(RecoveryKey()) }),
            ("email", { fixture in
                let change = EmailSettingsChange(settings: EmailRoutesTests.settings, password: "password")
                let answer = try await fixture.send(.put, HiveEndpoint.email, json: change)
                guard answer.status == .ok else { throw APIFixtureError.unexpectedStatus(answer.status) }
            }),
            ("a backup drive", { fixture in
                try BackupDriveStore(database: fixture.signIn.database).choose(
                    BackupDriveIdentity(volumeUUID: UUID(), name: "Drive"), by: fixture.signIn.device.id, at: fixture.signIn.clock.now
                )
            }),
        ]

        for (description, setUp) in setUps {
            let new = try APIFixture()
            try await setUp(new)
            let before = try new.snapshotOfState()

            // Act and Assert
            #expect(throws: RestoreError.refused(.alreadySetUp), "with \(description)") { try new.restore(file, key: key) }
            #expect(try new.snapshotOfState() == before)
            let state = try await new.send(.get, HiveEndpoint.restore).decoded(as: RestoreState.self)
            #expect(!state.canRestore)
        }
    }

    @Test("A new Hive says it can be restored, and once restored, that it can't")
    func reportsCanRestore() async throws {
        // Arrange
        let old = try APIFixture()
        _ = try await old.addEverything()
        let key = RecoveryKey()
        try await old.saveRecoveryKey(key)
        let new = try APIFixture()
        let before = try await new.send(.get, HiveEndpoint.restore).decoded(as: RestoreState.self)

        // Act
        _ = try new.restore(Data(contentsOf: old.recoveryFile), key: key)
        let after = try await new.send(.get, HiveEndpoint.restore).decoded(as: RestoreState.self)

        // Assert
        #expect(before == RestoreState(canRestore: true, retentionPausedSince: nil, servers: []))
        #expect(!after.canRestore)
        #expect(after.retentionPausedSince == new.signIn.clock.now)
        #expect(after.servers.map(\.name) == [ConfigurationSamples.server.name])
    }
}

extension APIFixture {
    @discardableResult
    func restore(_ file: Data, key: RecoveryKey) throws -> RestoreOutcome {
        try api.restore.restore(RestoreRequest(file: file, recoveryKeyCode: key.code), isFromThisMac: true, by: signIn.device.id)
    }

    func sealedContents() throws -> RecoveryContents {
        try signIn.database.writer.read { try RecoveryContentsReader.sealedContents(writtenAt: .distantPast, in: $0) }
    }

    /// The configuration with every secret opened, as a recovery file would hold it.
    func openedContents() throws -> RecoveryContents {
        try sealedContents().mappingSecrets { try sealer.open(SealedSecret(data: $0)) }
    }

    func recoveryKeyState() throws -> RecoveryKeyState {
        try RecoveryKeyStore(database: signIn.database).state()
    }

    /// What a refused restore must leave as it was.
    func snapshotOfState() throws -> [String] {
        [
            try signIn.database.hiveID().uuidString,
            String(describing: try sealedContents()),
            String(describing: try auditEvents()),
            String(restart.isRequested),
        ]
    }
}
