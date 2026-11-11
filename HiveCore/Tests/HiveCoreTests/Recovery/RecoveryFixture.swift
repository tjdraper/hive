import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird

extension APIFixture {
    var recoveryFile: URL {
        keyFolder.url.appending(path: RecoveryFileWriter.fileName, directoryHint: .notDirectory)
    }

    /// Gives the fixture's Hive `key`, confirmed, as Beekeeper would.
    @discardableResult
    func saveRecoveryKey(_ key: RecoveryKey) async throws -> RecoveryKeyState {
        let change = RecoveryKeyChange(publicKey: key.publicKey.rawRepresentation)
        let answer = try await sendConfirmed(.put, HiveEndpoint.recoveryKey, json: change)
        guard answer.status == .ok else { throw APIFixtureError.unexpectedStatus(answer.status) }
        return try answer.decoded(as: RecoveryKeyState.self)
    }

    func openRecoveryFile(with key: RecoveryKey) throws -> RecoveryContents {
        try RecoveryFile.open(Data(contentsOf: recoveryFile), with: key.privateKey)
    }

    /// A server with a confirmed host key, a job with a database password, a chosen backup drive and
    /// email with a password: one of every kind of secret.
    func addEverything() async throws -> (server: Server, job: BackupJob) {
        let server = try await addServer()
        try await confirmHostKey(of: server)
        let job = try await addJob(to: server)
        try BackupDriveStore(database: signIn.database).choose(
            BackupDriveIdentity(volumeUUID: UUID(), name: "Test Drive"),
            by: signIn.device.id,
            at: signIn.clock.now
        )
        let email = EmailSettingsChange(settings: EmailRoutesTests.settings, password: RecoveryFileTests.smtpPassword)
        let answer = try await send(.put, HiveEndpoint.email, json: email)
        guard answer.status == .ok else { throw APIFixtureError.unexpectedStatus(answer.status) }
        return (server, job)
    }
}
