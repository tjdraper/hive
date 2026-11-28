import Foundation
@testable import hive_scout
@testable import ScoutCore
import ScoutProtocol
import Testing

/// Installing on a Mac, into a temporary root, as a LaunchDaemon with a hidden system user.
struct MacInstallTests {
    private static let code = FakeHive().code(hosts: ["100.64.0.1"])
    private static let label = "com.buzzingpixel.hive-scout"

    private let server: TemporaryServer
    private let system: FakeServerSystem
    private let source: URL
    private let said = Recorded<String>()

    init() throws {
        server = try TemporaryServer()
        system = FakeServerSystem(layout: InstallLayout(root: server.root.path(percentEncoded: false), system: .mac))
        source = server.root.appending(path: "download/hive-scout")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary 1".utf8).write(to: source)
        // No /usr/local/bin, as on a new Mac.
        for folder in ["/usr", "/Library/LaunchDaemons", "/Library/Application Support", "/etc/sudoers.d"] {
            let url = server.root.appending(path: String(folder.dropFirst()))
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        for tool in ["/bin/launchctl", "/usr/bin/dscl"] {
            try server.write(tool, "")
            chmod(system.layout.onDisk(tool), 0o755)
        }
        // macOS's own users take the top of the range.
        system.takenIDs = [499]
        system.answers["launchctl print"] = CommandResult(status: 113, output: "Could not find service")
    }

    private var layout: InstallLayout {
        system.layout
    }

    private func install(code: EnrollmentCode?) throws(InstallError) {
        try InstallWorkflow(layout: layout, system: system, source: source.path(percentEncoded: false), say: { [said] in said.append($0) })
            .install(sshUser: nil) { code }
    }

    private func text(_ path: String) -> String? {
        try? String(contentsOfFile: layout.onDisk(path), encoding: .utf8)
    }

    private func everything() throws -> Set<String> {
        Set(try FileManager.default.subpathsOfDirectory(atPath: server.root.path(percentEncoded: false)))
    }

    @Test("A first install makes a hidden system user with a free ID, the binary's folder, and the LaunchDaemon, and loads it")
    func installs() throws {
        // Act
        try install(code: Self.code)

        // Assert
        #expect(text(layout.binary) == "binary 1")
        #expect(text(layout.launchDaemon) == InitSystem.launchd.serviceFile(for: layout).text)
        let state = try FileManager.default.attributesOfItem(atPath: layout.onDisk("/Library/Application Support/Hive Scout"))
        #expect(state[.posixPermissions] as? Int == 0o700)
        #expect(system.users["_hive-scout"] == SystemUser(uid: 498, gid: 498))
        #expect(system.enrolledCodes == [Self.code.text])
        #expect(system.ran == [
            "dscl . -create /Groups/_hive-scout PrimaryGroupID 498",
            "dscl . -create /Groups/_hive-scout RealName Hive Scout",
            "dscl . -create /Groups/_hive-scout Password *",
            "dscl . -create /Users/_hive-scout UniqueID 498",
            "dscl . -create /Users/_hive-scout PrimaryGroupID 498",
            "dscl . -create /Users/_hive-scout UserShell /usr/bin/false",
            "dscl . -create /Users/_hive-scout NFSHomeDirectory /var/empty",
            "dscl . -create /Users/_hive-scout RealName Hive Scout",
            "dscl . -create /Users/_hive-scout Password *",
            "dscl . -create /Users/_hive-scout IsHidden 1",
            "launchctl print system/\(Self.label)",
            "launchctl enable system/\(Self.label)",
            "launchctl bootstrap system /Library/LaunchDaemons/\(Self.label).plist",
        ])
    }

    @Test("Running again with a new binary restarts the loaded service, and a new code alone only reloads it")
    func runAgain() throws {
        // Arrange
        try install(code: Self.code)
        system.answers["launchctl print"] = nil
        try Data("binary 2".utf8).write(to: source)
        system.commands = []

        // Act
        try install(code: nil)
        let updated = system.ran
        system.commands = []
        try install(code: Self.code)

        // Assert
        #expect(text(layout.binary) == "binary 2")
        #expect(updated == ["launchctl print system/\(Self.label)", "launchctl kickstart -k system/\(Self.label)"])
        #expect(system.ran == ["launchctl print system/\(Self.label)", "launchctl kill SIGHUP system/\(Self.label)"])
    }

    @Test("A service file that changed is loaded again, since launchd reads it only when it's loaded")
    func serviceChanged() throws {
        // Arrange
        try install(code: Self.code)
        system.answers["launchctl print"] = nil
        try server.write(layout.launchDaemon, "an older service")
        system.commands = []

        // Act
        try install(code: nil)

        // Assert
        #expect(system.ran == [
            "launchctl print system/\(Self.label)",
            "launchctl bootout system/\(Self.label)",
            "launchctl enable system/\(Self.label)",
            "launchctl bootstrap system /Library/LaunchDaemons/\(Self.label).plist",
        ])
    }

    @Test("A binary folder others can change is refused before anything changes, since root runs what's in it")
    func binaryFolderOthersCanChange() throws {
        // Arrange
        try FileManager.default.createDirectory(at: server.root.appending(path: "usr/local/bin"), withIntermediateDirectories: true)
        system.foldersOthersCanChange = [layout.onDisk("/usr/local/bin")]
        let before = try everything()

        // Act
        let error: InstallError?
        do {
            try install(code: Self.code)
            error = nil
        } catch let refusal {
            error = refusal
        }

        // Assert
        #expect(error == .binaryFolderNotRoots("/usr/local/bin"))
        #expect(InstallMessage.text(for: .binaryFolderNotRoots("/usr/local/bin")).contains("Nothing was installed"))
        #expect(try everything() == before)
        #expect(system.commands.isEmpty)
        #expect(system.enrolledCodes.isEmpty)
    }

    @Test("Without /usr/local/bin, the nearest folder above it is the one checked")
    func missingBinaryFolder() throws {
        // Arrange
        system.foldersOthersCanChange = [layout.onDisk("/usr")]

        // Act, Assert
        #expect(throws: InstallError.binaryFolderNotRoots("/usr")) { try install(code: Self.code) }
    }

    @Test("Uninstall unloads the service and removes it, the binary, the state folder, the user and the group")
    func uninstall() throws {
        // Arrange
        try FileManager.default.createDirectory(at: server.root.appending(path: "usr/local/bin"), withIntermediateDirectories: true)
        let before = try everything()
        try install(code: Self.code)
        system.commands = []

        // Act
        try UninstallWorkflow(layout: layout, system: system, say: { [said] in said.append($0) }).uninstall()

        // Assert
        #expect(try everything() == before)
        #expect(system.users["_hive-scout"] == nil)
        #expect(!system.groups.contains("_hive-scout"))
        #expect(system.ran == [
            "launchctl bootout system/\(Self.label)",
            "dscl . -delete /Users/_hive-scout",
            "dscl . -delete /Groups/_hive-scout",
        ])
    }

    @Test("New addresses reload the running service through launchd")
    func newAddresses() throws {
        // Arrange
        try install(code: Self.code)
        system.commands = []

        // Act
        try NewAddressesWorkflow(layout: layout, system: system, source: "/usr/local/bin/hive-scout")
            .replace(with: [EnrollmentCode.Address(host: "100.64.0.9", port: 4484)])

        // Assert
        #expect(system.ran == ["launchctl kill SIGHUP system/\(Self.label)"])
    }
}
