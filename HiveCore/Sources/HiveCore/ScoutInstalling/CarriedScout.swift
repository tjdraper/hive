import CryptoKit
import Foundation
import HiveKit
import ScoutProtocol

/// The release of Scout Hive.app carries: its version, and its binaries in `Contents/Resources/Scout`,
/// each with its signed statement, so a server never has to reach GitHub. The installed Scout checks an
/// update's signature itself; Hive checks only that each binary is the one its statement names.
public struct CarriedScout: Sendable {
    struct Release: Sendable {
        let version: ScoutVersion
        /// As the statement's file holds it.
        let statement: String
        let binary: Data
        /// In lower-case hex.
        let sha256: String
    }

    let folder: URL
    /// From Hive.app's Info.plist, against which servers' Scouts are out of date. Hive's own version plays
    /// no part, so a release of Hive that leaves Scout alone doesn't ask for every Scout to be updated.
    let version: String?

    /// Beside the daemon in Hive.app: `Contents/MacOS/HiveDaemon` to `Contents/Resources/Scout`.
    public init(besideExecutable executable: URL, version: String?) {
        let contents = executable.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        self.init(folder: contents.appending(path: "Resources/Scout", directoryHint: .isDirectory), version: version)
    }

    init(folder: URL, version: String?) {
        self.folder = folder
        self.version = version
    }

    /// Nil when Hive.app carries none for the platform, or its statement doesn't name its binary.
    func release(for platform: ScoutRelease.Platform) -> Release? {
        let binaryFile = folder.appending(path: "hive-scout-linux-\(platform.cpu)", directoryHint: .notDirectory)
        guard let statementText = try? String(contentsOf: binaryFile.appendingPathExtension("statement"), encoding: .utf8),
              let (statement, _) = ReleaseStatement.parse(statementText),
              statement.platform == "linux-\(platform.cpu)",
              let binary = try? Data(contentsOf: binaryFile),
              Array(SHA256.hash(data: binary)) == statement.sha256
        else { return nil }
        let sha256 = statement.sha256.map { String(format: "%02x", $0) }.joined()
        return Release(version: statement.version, statement: statementText, binary: binary, sha256: sha256)
    }
}
