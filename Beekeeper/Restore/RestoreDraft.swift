import CryptoKit
import Foundation
import HiveKit
import Observation
import os

/// What restoring a Hive needs from the person: one of its recovery files and the recovery key that
/// opens it. The key is checked against the file here, so a key for another file is caught before it's
/// sent. Only Beekeeper on the Hive's own Mac sends them, over its local connection.
@Observable
final class RestoreDraft {
    private static let logger = Logger(subsystem: BeekeeperLog.subsystem, category: "Restore")

    struct ChosenFile: Equatable {
        let url: URL
        let data: Data
    }

    var file: ChosenFile?
    var code = ""
    private(set) var isRestoring = false
    private(set) var failure: String?

    /// Why the file or key can't be used, once both are there.
    var problem: String? {
        if let file, RecoveryFileHeader.publicKey(of: file.data) == nil {
            return "This isn't a recovery file this Beekeeper can read."
        }
        guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let key: RecoveryKey
        do {
            key = try RecoveryKey(code: code)
        } catch .wrongLength {
            return code.filter { $0.isLetter || $0.isNumber }.count < RecoveryKey.groupCount * RecoveryKey.groupLength
                ? nil
                : "The key is too long. It's 8 groups of 4 characters."
        } catch .unknownCharacter {
            return "The key has a character recovery keys don't use."
        } catch {
            return "The key isn't right. Check for a mistyped character."
        }
        if let file, RecoveryFileHeader.publicKey(of: file.data) != key.publicKey.rawRepresentation {
            return "This key doesn't open this recovery file. It may be for another Hive, or replaced since."
        }
        return nil
    }

    var isComplete: Bool {
        file != nil && (try? RecoveryKey(code: code)) != nil && problem == nil
    }

    /// Nil when it wasn't restored, with `failure` saying why.
    func restore(on link: HiveLink) async -> RestoreOutcome? {
        guard let file else { return nil }
        isRestoring = true
        defer { isRestoring = false }
        do {
            let request = RestoreRequest(file: file.data, recoveryKeyCode: code)
            let outcome: RestoreOutcome = try await link.perform { try await $0.post(HiveEndpoint.restore, body: request) }
            failure = nil
            Self.logger.notice("Restored the Hive from a recovery file")
            return outcome
        } catch let refused as HiveRequestError {
            failure = (try? JSONDecoder().decode(RestoreRefusal.self, from: refused.body)).map { Self.message(for: $0.problem) }
                ?? HiveLink.message(for: refused)
        } catch {
            failure = HiveLink.message(for: error)
        }
        return nil
    }

    private static func message(for problem: RestoreProblem) -> String {
        switch problem {
        case .notOnThisMac: "Only Beekeeper on the Hive's own Mac can restore it."
        case .alreadySetUp: "This Hive is set up already, so it can't be restored over."
        case .mistypedKey: "The key isn't right. Check for a mistyped character."
        case .notARecoveryFile: "This isn't a recovery file."
        case .unsupportedFile: "This recovery file was written by a newer Hive. Update Hive first."
        case .otherKey: "This key doesn't open this recovery file."
        case .couldNotOpen: "The recovery file couldn't be opened. It may have been changed or cut short."
        }
    }
}
