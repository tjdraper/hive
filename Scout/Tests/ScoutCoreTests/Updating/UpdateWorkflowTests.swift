import Crypto
import Foundation
@testable import ScoutCore
import ScoutProtocol
import Testing

struct UpdateWorkflowTests {
    private static let releaseKey = Curve25519.Signing.PrivateKey()
    private static let developmentKey = Curve25519.Signing.PrivateKey()
    private static let installed = ScoutVersion(0, 9, 0)
    private static let platform = "linux-x86_64"
    private static let newBinary = Array("binary 0.10.0".utf8)

    private let server: TemporaryServer
    private let system: FakeServerSystem

    init() throws {
        server = try TemporaryServer()
        system = FakeServerSystem(layout: InstallLayout(root: server.root.path(percentEncoded: false)))
        try server.write(system.layout.binary, "binary 0.9.0")
    }

    private var installedPath: String {
        system.layout.onDisk(system.layout.binary)
    }

    private func installedBytes() throws -> [UInt8] {
        try Array(Data(contentsOf: URL(filePath: installedPath)))
    }

    /// A statement file for `binary`, signed with `key`.
    private static func statement(
        version: ScoutVersion = ScoutVersion(0, 10, 0),
        platform: String = platform,
        for binary: [UInt8] = newBinary,
        signedWith key: Curve25519.Signing.PrivateKey = releaseKey
    ) throws -> String {
        let statement = ReleaseStatement(version: version, platform: platform, sha256: Array(SHA256.hash(data: binary)))
        let signature = try key.signature(for: Array(statement.signedText.utf8))
        return statement.signedText + "signature \(signature.base64EncodedString())\n"
    }

    private func update(
        _ statement: String,
        binary: [UInt8] = newBinary,
        trusting key: Curve25519.Signing.PrivateKey? = releaseKey
    ) throws(UpdateError) -> ScoutVersion {
        try UpdateWorkflow(
            layout: system.layout,
            system: system,
            trustedKey: key?.publicKey,
            installedVersion: Self.installed,
            platform: Self.platform
        ).update(statement: statement, binary: binary)
    }

    private func refusal(
        _ statement: String,
        binary: [UInt8] = newBinary,
        trusting key: Curve25519.Signing.PrivateKey? = releaseKey
    ) -> UpdateError? {
        do {
            _ = try update(statement, binary: binary, trusting: key)
            return nil
        } catch {
            return error
        }
    }

    @Test("A newer release signed with the trusted key replaces the binary, which then installs itself and restarts")
    func updates() throws {
        // Act
        let version = try update(Self.statement())

        // Assert
        #expect(version == ScoutVersion(0, 10, 0))
        #expect(try installedBytes() == Self.newBinary)
        let mode = try FileManager.default.attributesOfItem(atPath: installedPath)[.posixPermissions] as? Int
        #expect(mode == 0o755)
        #expect(system.ran == ["hive-scout install"])
        #expect(!FileManager.default.fileExists(atPath: installedPath + ".new"))
    }

    @Test("Every update that isn't a genuine, newer release for this server is refused, and the installed binary stays")
    func refusals() throws {
        let other = Array("another binary".utf8)
        var edited = try Self.statement(version: ScoutVersion(0, 8, 0))
        edited = edited.replacingOccurrences(of: "version 0.8.0", with: "version 0.11.0")
        let zeros = Data(repeating: 0, count: 64).base64EncodedString()
        let hash = Array(SHA256.hash(data: Self.newBinary))
        let unsigned = ReleaseStatement(version: ScoutVersion(0, 10, 0), platform: Self.platform, sha256: hash).signedText
            + "signature \(zeros)\n"
        let older = ScoutVersion(0, 8, 9)

        #expect(refusal("") == .notAStatement)
        #expect(refusal(unsigned) == .notSigned)
        #expect(refusal(try Self.statement(signedWith: Self.developmentKey)) == .notSigned)
        #expect(refusal(edited) == .notSigned)
        #expect(refusal(try Self.statement(platform: "linux-aarch64")) == .otherPlatform("linux-aarch64"))
        #expect(refusal(try Self.statement(), binary: other) == .hashMismatch)
        #expect(refusal(try Self.statement(version: Self.installed)) == .notNewer(installed: Self.installed, offered: Self.installed))
        #expect(refusal(try Self.statement(version: older)) == .notNewer(installed: Self.installed, offered: older))

        #expect(try installedBytes() == Array("binary 0.9.0".utf8))
        #expect(system.commands.isEmpty)
    }

    @Test("A release Scout refuses a development-signed update, and a development Scout a release-signed one")
    func keysDontCross() throws {
        #expect(refusal(try Self.statement(signedWith: Self.developmentKey), trusting: Self.releaseKey) == .notSigned)
        #expect(refusal(try Self.statement(signedWith: Self.releaseKey), trusting: Self.developmentKey) == .notSigned)
        #expect(try update(Self.statement(signedWith: Self.developmentKey), trusting: Self.developmentKey) == ScoutVersion(0, 10, 0))
    }

    @Test("A build without an update key, not run as root, or without Scout installed, takes no update")
    func cantUpdate() throws {
        #expect(refusal(try Self.statement(), trusting: nil) == .noUpdateKey)

        system.isRoot = false
        #expect(refusal(try Self.statement()) == .notRoot)
        system.isRoot = true

        try FileManager.default.removeItem(atPath: installedPath)
        #expect(refusal(try Self.statement()) == .notInstalled)
        #expect(system.commands.isEmpty)
    }

    @Test("What's installed is the binary that was checked, never a file left where it's staged")
    func stagedFileIgnored() throws {
        // Arrange: a different binary where the new one is staged, then a link from there to another file.
        let staged = installedPath + ".new"
        try Data("planted".utf8).write(to: URL(filePath: staged))

        // Act
        _ = try update(Self.statement())

        // Assert
        #expect(try installedBytes() == Self.newBinary)

        // Arrange
        let elsewhere = server.root.appending(path: "elsewhere").path(percentEncoded: false)
        try Data("elsewhere".utf8).write(to: URL(filePath: elsewhere))
        try FileManager.default.createSymbolicLink(atPath: staged, withDestinationPath: elsewhere)

        // Act
        let error = refusal(try Self.statement(version: ScoutVersion(0, 11, 0)))

        // Assert
        guard case .file = error else {
            Issue.record("expected a file error, got \(String(describing: error))")
            return
        }
        #expect(try installedBytes() == Self.newBinary)
        #expect(try Data(contentsOf: URL(filePath: elsewhere)) == Data("elsewhere".utf8))
    }

    @Test("A new binary whose service doesn't start again is reported, not taken as done")
    func restartFails() throws {
        system.answers["hive-scout"] = CommandResult(status: 1, output: "systemctl restart hive-scout failed")
        #expect(refusal(try Self.statement()) == .restartFailed(output: "systemctl restart hive-scout failed"))
    }
}
