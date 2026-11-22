#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import Crypto
import ScoutProtocol
import ScoutUpdateKey

public enum UpdateError: Error, Equatable {
    case notRoot
    case notInstalled
    /// This build was given no key to check updates with, so it takes none.
    case noUpdateKey
    case notAStatement
    /// Signed with another key, such as the development key for a release Scout, or not at all.
    case notSigned
    case otherPlatform(String)
    case hashMismatch
    case notNewer(installed: ScoutVersion, offered: ScoutVersion)
    case file(InstalledFileError)
    /// The new binary is in place, but installing its service and starting it again failed.
    case restartFailed(output: String)
}

/// `hive-scout manage`'s update, run as root: replaces the installed binary with a newer release,
/// only once its statement is signed with the key this build trusts, is for this system and CPU,
/// matches the binary's hash, and names a newer version. Hive's SSH user may run this through
/// Scout's `sudo` or `doas` rule, so a Hive taken over by someone else can install only genuine,
/// newer releases.
///
/// Never reads Scout's state folder, which Scout's own user can change.
public struct UpdateWorkflow {
    let layout: InstallLayout
    let system: any ServerSystem
    let trustedKey: Curve25519.Signing.PublicKey?
    /// The running binary's, which through Scout's rule is the installed one.
    let installedVersion: ScoutVersion
    let platform: String

    public init() {
        self.init(
            layout: .server,
            system: PosixServerSystem(),
            trustedKey: Self.builtInKey,
            installedVersion: ScoutRelease.version,
            platform: ScoutRelease.platform
        )
    }

    init(
        layout: InstallLayout,
        system: any ServerSystem,
        trustedKey: Curve25519.Signing.PublicKey?,
        installedVersion: ScoutVersion,
        platform: String
    ) {
        self.layout = layout
        self.system = system
        self.trustedKey = trustedKey
        self.installedVersion = installedVersion
        self.platform = platform
    }

    /// The key `Scripts/build-scout.sh` built this binary to trust: the release key for a release,
    /// the development key otherwise.
    static var builtInKey: Curve25519.Signing.PublicKey? {
        guard let text = scout_update_public_key(), let raw = Data(base64Encoded: String(cString: text)) else { return nil }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }

    /// - Parameter binary: held in memory from the moment it's read, so the bytes checked are the
    ///   bytes installed, whatever happens to any file meanwhile.
    /// - Returns: the version now installed.
    public func update(statement file: String, binary: [UInt8]) throws(UpdateError) -> ScoutVersion {
        guard system.isRoot else { throw .notRoot }
        guard access(layout.onDisk(layout.binary), F_OK) == 0 else { throw .notInstalled }
        guard let trustedKey else { throw .noUpdateKey }
        guard let (statement, signature) = ReleaseStatement.parse(file) else { throw .notAStatement }
        guard trustedKey.isValidSignature(signature, for: Array(statement.signedText.utf8)) else { throw .notSigned }
        guard statement.platform == platform else { throw .otherPlatform(statement.platform) }
        guard Array(SHA256.hash(data: binary)) == statement.sha256 else { throw .hashMismatch }
        guard statement.version > installedVersion else {
            throw .notNewer(installed: installedVersion, offered: statement.version)
        }

        // Staged beside the installed binary, in a folder only root can write, and renamed over it,
        // so the server always has one whole binary.
        let path = layout.onDisk(layout.binary)
        do {
            try InstalledFile.putInPlace(InstalledFile.stage(binary, for: path, mode: 0o755), at: path)
        } catch {
            throw .file(error)
        }
        // The new release installs itself over its own files, keeping the enrollment, so one that
        // changes its service brings the change, and restarts the service.
        let result = system.run([layout.binary, "install"])
        guard result.status == 0 else { throw .restartFailed(output: result.output) }
        return statement.version
    }
}
