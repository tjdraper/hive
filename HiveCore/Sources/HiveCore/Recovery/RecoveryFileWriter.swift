import CryptoKit
import Foundation
import GRDB
import os

/// Keeps a current recovery file in Hive's data directory (§14), where the Mac's own backup picks it up:
/// written soon after the configuration changes, and once a day either way.
///
/// It notices a change by comparing a hash of the configuration with its secrets still sealed, so it
/// opens secrets only to write. A secret entered again is sealed afresh, so its change shows too.
/// Writing is one step on the actor with nothing awaited, so a file written for an old key can't land
/// after a new key's has replaced it.
actor RecoveryFileWriter {
    static let fileName = "recovery.\(RecoveryFile.fileExtension)"
    static let checkInterval: Duration = .seconds(30)
    static let rewriteInterval: TimeInterval = 24 * 60 * 60

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Recovery")

    private let database: HiveDatabase
    private let keys: RecoveryKeyStore
    private let sealer: SecretSealer
    private let file: OwnerOnlyFile
    private let now: @Sendable () -> Date
    /// Forgotten when Hive stops, so it writes a file on every start.
    private var lastWritten: (fingerprint: Data, at: Date)?
    /// So a failure that keeps happening is logged once, not on every check.
    private var lastFailure: String?

    init(database: HiveDatabase, sealer: SecretSealer, directory: URL, now: @escaping @Sendable () -> Date) {
        self.database = database
        keys = RecoveryKeyStore(database: database)
        self.sealer = sealer
        file = OwnerOnlyFile(url: directory.appending(path: Self.fileName, directoryHint: .notDirectory))
        self.now = now
    }

    /// Until the task running it is cancelled.
    func run() async {
        while !Task.isCancelled {
            writeIfDue()
            try? await Task.sleep(for: Self.checkInterval)
        }
    }

    /// Writes the file when the configuration or key changed since it was last written, it's a day old,
    /// or it's gone. Returns whether it wrote one.
    @discardableResult
    func writeIfDue() -> Bool {
        do {
            let date = now()
            let (key, sealed) = try database.writer.read { database in
                (try RecoveryKeyStore.publicKey(in: database), try RecoveryContentsReader.sealedContents(writtenAt: date, in: database))
            }
            guard let key else { return false }

            let fingerprint = try Self.fingerprint(of: sealed, key: key)
            if let lastWritten, lastWritten.fingerprint == fingerprint,
               date.timeIntervalSince(lastWritten.at) < Self.rewriteInterval,
               FileManager.default.fileExists(atPath: file.url.fileSystemPath) {
                return false
            }

            let contents = try sealed.mappingSecrets { try sealer.open(SealedSecret(data: $0)) }
            try file.replace(RecoveryFile.seal(contents, to: key))
            try keys.recordFileWritten(at: date, with: key)
            lastWritten = (fingerprint, date)
            lastFailure = nil
            let jobCount = contents.servers.flatMap(\.jobs).count
            Self.logger.notice(
                "Wrote the recovery file (\(contents.servers.count, privacy: .public) servers, \(jobCount, privacy: .public) jobs)"
            )
            return true
        } catch {
            let failure = String(describing: error)
            if failure != lastFailure {
                Self.logger.error("Couldn't write the recovery file: \(failure, privacy: .public)")
                lastFailure = failure
            }
            return false
        }
    }

    /// After a new recovery key: the old file only opens with the old key, so it goes first, and is
    /// gone even when the new one can't be written yet.
    @discardableResult
    func startOver() -> Bool {
        lastWritten = nil
        do {
            try file.remove()
            Self.logger.notice("Cleared any recovery file written with an older key")
        } catch {
            Self.logger.error("Couldn't remove the old recovery file: \(String(describing: error), privacy: .public)")
        }
        return writeIfDue()
    }

    /// Hashes the date it's written out with everything else, since that changes on every check.
    private static func fingerprint(of sealed: RecoveryContents, key: Curve25519.KeyAgreement.PublicKey) throws -> Data {
        let undated = RecoveryContents(
            format: sealed.format,
            writtenAt: .distantPast,
            hive: sealed.hive,
            servers: sealed.servers,
            email: sealed.email
        )
        var hash = SHA256()
        hash.update(data: key.rawRepresentation)
        hash.update(data: try undated.encoded())
        return Data(hash.finalize())
    }
}
