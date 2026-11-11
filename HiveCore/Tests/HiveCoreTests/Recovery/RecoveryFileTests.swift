import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct RecoveryFileTests {
    static let smtpPassword = "smtp password"

    @Test("A recovery file opens with its key and holds the Hive ID, the configuration and every kind of secret")
    func holdsEverything() async throws {
        // Arrange
        let fixture = try APIFixture()
        let (server, job) = try await fixture.addEverything()
        let key = RecoveryKey()

        // Act
        let state = try await fixture.saveRecoveryKey(key)
        let contents = try fixture.openRecoveryFile(with: key)

        // Assert
        #expect(state.fileWrittenAt == fixture.signIn.clock.now)
        #expect(contents.format == RecoveryContents.currentFormat)
        #expect(try contents.hive.id == fixture.signIn.database.hiveID())
        #expect(contents.hive.name == "Test Hive")
        #expect(contents.hive.backupDrive?.name == "Test Drive")

        let recovered = try #require(contents.servers.only)
        #expect(recovered.id == server.id)
        #expect(recovered.host == server.connection.host)
        #expect(recovered.user == server.connection.user)
        #expect(recovered.quotaBytes == server.quotaBytes)
        #expect(recovered.hostKey == ConfigurationSamples.hostKey.line)
        let sshKey = try #require(recovered.sshKey)
        #expect(try SSHKeyPair(seed: sshKey.seed).publicKey.fingerprint == server.sshKeyFingerprint)

        let recoveredJob = try #require(recovered.jobs.only)
        #expect(recoveredJob.id == job.id)
        #expect(recoveredJob.directories.map(\.folder) == job.directories.map(\.folder))
        #expect(recoveredJob.minutesOfDay == [150, 840])
        #expect(recoveredJob.dailySnapshots == job.retention.dailySnapshots)
        let database = try #require(recoveredJob.databases.only)
        #expect(database.id == job.databases.first?.id)
        #expect(database.serviceName == "site_db")
        #expect(database.password == Data(ConfigurationSamples.password.utf8))

        #expect(contents.email?.host == EmailRoutesTests.settings.host)
        #expect(contents.email?.password == Data(Self.smtpPassword.utf8))
    }

    @Test("A recovery file doesn't open with another key")
    func refusesWrongKey() async throws {
        // Arrange
        let fixture = try APIFixture()
        _ = try await fixture.addEverything()
        try await fixture.saveRecoveryKey(RecoveryKey())
        let other = RecoveryKey()
        var claimingOther = try Data(contentsOf: fixture.recoveryFile)
        let keyStart = RecoveryFile.magic.count + 1
        claimingOther.replaceSubrange(keyStart ..< keyStart + RecoveryFile.keyLength, with: other.publicKey.rawRepresentation)

        // Act and Assert
        #expect(throws: RecoveryFileError.otherKey) { try fixture.openRecoveryFile(with: other) }
        #expect(throws: RecoveryFileError.couldNotOpen) { try RecoveryFile.open(claimingOther, with: other.privateKey) }
    }

    @Test("A recovery file with any byte changed doesn't open")
    func refusesChangedByte() async throws {
        // Arrange
        let fixture = try APIFixture()
        _ = try await fixture.addEverything()
        let key = RecoveryKey()
        try await fixture.saveRecoveryKey(key)
        let file = try Data(contentsOf: fixture.recoveryFile)

        for index in file.indices {
            var changed = file
            changed[index] ^= 0x01

            // Act and Assert
            #expect(throws: (any Error).self, "byte \(index)") { try RecoveryFile.open(changed, with: key.privateKey) }
        }
        #expect(throws: (any Error).self) { try RecoveryFile.open(file.dropLast(), with: key.privateKey) }
    }

    @Test("After a new key, the old file is gone and the new one doesn't open with the old key")
    func newKeyReplacesOldFile() async throws {
        // Arrange
        let fixture = try APIFixture()
        _ = try await fixture.addEverything()
        let old = RecoveryKey()
        try await fixture.saveRecoveryKey(old)
        let oldFile = try Data(contentsOf: fixture.recoveryFile)
        let new = RecoveryKey()

        // Act
        let state = try await fixture.saveRecoveryKey(new)

        // Assert
        #expect(throws: RecoveryFileError.otherKey) { try fixture.openRecoveryFile(with: old) }
        #expect(try fixture.openRecoveryFile(with: new).hive.id == fixture.signIn.database.hiveID())
        #expect(try Data(contentsOf: fixture.recoveryFile) != oldFile)
        let recoveryFiles = try FileManager.default.contentsOfDirectory(atPath: fixture.keyFolder.url.fileSystemPath)
            .filter { $0.hasPrefix("recovery.") }
        #expect(recoveryFiles == [RecoveryFileWriter.fileName])
        #expect(state.fileWrittenAt != nil)
        #expect(try fixture.auditEvents().prefix(2) == [
            .recoveryKeySaved(replacedAnother: true),
            .recoveryKeySaved(replacedAnother: false),
        ])
    }

    @Test("Saving the key the Hive already has changes nothing")
    func sameKeyChangesNothing() async throws {
        // Arrange
        let fixture = try APIFixture()
        let key = RecoveryKey()
        try await fixture.saveRecoveryKey(key)
        let before = try fixture.auditEvents()

        // Act
        try await fixture.saveRecoveryKey(key)

        // Assert
        #expect(try fixture.auditEvents() == before)
    }

    @Test("Without a recovery key, no file is written")
    func noKeyNoFile() async throws {
        // Arrange
        let fixture = try APIFixture()
        _ = try await fixture.addEverything()

        // Act
        let wrote = await fixture.api.recoveryFiles.writeIfDue()
        let state = try await fixture.send(.get, HiveEndpoint.recoveryKey).decoded(as: RecoveryKeyState.self)

        // Assert
        #expect(!wrote)
        #expect(!FileManager.default.fileExists(atPath: fixture.recoveryFile.fileSystemPath))
        #expect(!state.hasKey)
        #expect(state.fileWrittenAt == nil)
    }

    @Test("The file is written again after a configuration change, and not before")
    func rewritesAfterChange() async throws {
        // Arrange
        let fixture = try APIFixture()
        let key = RecoveryKey()
        try await fixture.saveRecoveryKey(key)
        let writer = fixture.api.recoveryFiles
        let unchanged = await writer.writeIfDue()

        // Act
        let server = try await fixture.addServer()
        let afterChange = await writer.writeIfDue()

        // Assert
        #expect(!unchanged)
        #expect(afterChange)
        #expect(try fixture.openRecoveryFile(with: key).servers.map(\.id) == [server.id])
    }

    @Test("A secret entered again is written again, even with the same value")
    func rewritesAfterSecretEnteredAgain() async throws {
        // Arrange
        let fixture = try APIFixture()
        _ = try await fixture.addEverything()
        try await fixture.saveRecoveryKey(RecoveryKey())
        let email = EmailSettingsChange(settings: EmailRoutesTests.settings, password: Self.smtpPassword)

        // Act
        _ = try await fixture.send(.put, HiveEndpoint.email, json: email)
        let wrote = await fixture.api.recoveryFiles.writeIfDue()

        // Assert
        #expect(wrote)
    }

    @Test("The file is written again once a day, and when it's gone")
    func rewritesDailyAndWhenMissing() async throws {
        // Arrange
        let fixture = try APIFixture()
        try await fixture.saveRecoveryKey(RecoveryKey())
        let writer = fixture.api.recoveryFiles

        // Act
        fixture.signIn.clock.advance(by: RecoveryFileWriter.rewriteInterval - 1)
        let beforeADay = await writer.writeIfDue()
        fixture.signIn.clock.advance(by: 1)
        let afterADay = await writer.writeIfDue()
        try FileManager.default.removeItem(at: fixture.recoveryFile)
        let afterRemoval = await writer.writeIfDue()
        let state = try await fixture.send(.get, HiveEndpoint.recoveryKey).decoded(as: RecoveryKeyState.self)

        // Assert
        #expect(!beforeADay)
        #expect(afterADay)
        #expect(afterRemoval)
        #expect(state.fileWrittenAt == fixture.signIn.clock.now)
    }

    @Test("Only Hive's user can read or change the file")
    func ownerOnly() async throws {
        // Arrange
        let fixture = try APIFixture()

        // Act
        try await fixture.saveRecoveryKey(RecoveryKey())

        // Assert
        #expect(try permissions(of: fixture.recoveryFile.fileSystemPath) == 0o600)
    }

    @Test("A recovery key can't be saved without signing in, even with a confirmation")
    func refusesUnauthenticated() async throws {
        // Arrange
        let fixture = try APIFixture()
        let body = try JSONEncoder().encode(RecoveryKeyChange(publicKey: RecoveryKey().publicKey.rawRepresentation))
        let confirmation = try fixture.confirmation(.put, HiveEndpoint.recoveryKey, body: body)
        var headers = HTTPFields()
        headers[try #require(HTTPFields.Element.Name(ConfirmationProof.headerName))] = confirmation.headerValue

        // Act
        let status = try await fixture.application.test(.router) { [headers] client in
            try await client.execute(uri: HiveEndpoint.recoveryKey, method: .put, headers: headers, body: ByteBuffer(bytes: body)) {
                $0.status
            }
        }

        // Assert
        #expect(status == .unauthorized)
        #expect(try !RecoveryKeyStore(database: fixture.signIn.database).state().hasKey)
        #expect(!FileManager.default.fileExists(atPath: fixture.recoveryFile.fileSystemPath))
    }

    @Test("A key that isn't an X25519 public key is refused, changing nothing")
    func refusesMalformedKey() async throws {
        // Arrange
        let fixture = try APIFixture()
        let before = try fixture.auditEvents()

        // Act
        let answer = try await fixture.sendConfirmed(.put, HiveEndpoint.recoveryKey, json: RecoveryKeyChange(publicKey: Data(count: 31)))

        // Assert
        #expect(answer.status == .badRequest)
        #expect(try fixture.auditEvents() == before)
        #expect(try await !fixture.send(.get, HiveEndpoint.recoveryKey).decoded(as: RecoveryKeyState.self).hasKey)
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
