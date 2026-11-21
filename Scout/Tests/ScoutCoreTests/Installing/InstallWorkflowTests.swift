import Foundation
@testable import hive_scout
@testable import ScoutCore
import ScoutProtocol
import Testing

struct InstallWorkflowTests {
    private let server: TemporaryServer
    private let system: FakeServerSystem
    private let source: URL
    private let said = Recorded<String>()

    init() throws {
        server = try TemporaryServer()
        system = FakeServerSystem(layout: InstallLayout(root: server.root.path(percentEncoded: false)))
        source = server.root.appending(path: "download/hive-scout")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary 1".utf8).write(to: source)
        for folder in ["/usr/local/bin", "/var/lib", "/etc/systemd/system", "/etc/init.d", "/etc/sudoers.d", "/run"] {
            let url = server.root.appending(path: String(folder.dropFirst()))
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try server.write("/proc/self/mountinfo", "22 1 0:21 / /proc rw,nosuid - proc proc rw\n")
    }

    private var layout: InstallLayout {
        system.layout
    }

    /// A server started by systemd, or by OpenRC, with these programs.
    private func boot(_ initSystem: InitSystem, tools: [String]) throws {
        let marker = initSystem == .systemd ? "run/systemd/system" : "run/openrc"
        try FileManager.default.createDirectory(at: server.root.appending(path: marker), withIntermediateDirectories: true)
        for tool in tools + (initSystem == .systemd ? ["systemctl"] : ["openrc-run", "rc-service", "rc-update"]) {
            let inUsrBin = ["systemctl", "loginctl", "useradd", "userdel", "groupdel", "sudo", "visudo", "doas"].contains(tool)
            let path = (inUsrBin ? "/usr/bin/" : "/sbin/") + tool
            try server.write(path, "")
            chmod(server.root.path(percentEncoded: false) + path, 0o755)
        }
    }

    private func install(sshUser: String? = nil, code: EnrollmentCode?) throws(InstallError) {
        try InstallWorkflow(layout: layout, system: system, source: source.path(percentEncoded: false), say: { [said] in said.append($0) })
            .install(sshUser: sshUser) { code }
    }

    private func refusal(sshUser: String? = nil, code: EnrollmentCode? = nil) -> InstallError? {
        do {
            try install(sshUser: sshUser, code: code)
            return nil
        } catch {
            return error
        }
    }

    private func text(_ path: String) -> String? {
        try? String(contentsOfFile: layout.onDisk(path), encoding: .utf8)
    }

    private func mode(_ path: String) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: layout.onDisk(path))[.posixPermissions] as? Int)
    }

    /// Every file and folder under the root, as the server sees it.
    private func everything() throws -> Set<String> {
        let root = server.root.path(percentEncoded: false)
        let found = try FileManager.default.subpathsOfDirectory(atPath: root)
        return Set(found.map { "/" + $0 })
    }

    private static let code = FakeHive().code(hosts: ["100.64.0.1"])

    @Test("A first install copies the binary, makes Scout's user and folder, enrolls, and starts the systemd service")
    func installsUnderSystemd() throws {
        // Arrange
        try boot(.systemd, tools: ["useradd", "nologin"])

        // Act
        try install(code: Self.code)

        // Assert
        #expect(text(layout.binary) == "binary 1")
        #expect(try mode(layout.binary) == 0o755)
        #expect(try mode(layout.stateDirectory) == 0o700)
        #expect(try mode(layout.systemdUnit) == 0o644)
        #expect(text(layout.systemdUnit) == InitSystem.systemd.serviceFile(for: layout).text)
        #expect(system.users["hive-scout"] != nil)
        #expect(system.enrolledCodes == [Self.code.text])
        #expect(system.ran == [
            "useradd --system --user-group --no-create-home --home-dir /var/lib/hive-scout --shell /sbin/nologin hive-scout",
            "systemctl daemon-reload",
            "systemctl enable --quiet hive-scout",
            "systemctl restart hive-scout",
        ])
        // The code goes to the enrolling Scout on standard input, never as an argument.
        #expect(!system.commands.joined().contains { $0.contains("scout1:") })
    }

    @Test("Running again without a code replaces the binary and restarts, keeping the enrollment")
    func runAgain() throws {
        // Arrange
        try boot(.systemd, tools: ["useradd"])
        try install(code: Self.code)
        try Data("binary 2".utf8).write(to: source)
        system.commands = []

        // Act
        try install(code: nil)

        // Assert
        #expect(text(layout.binary) == "binary 2")
        #expect(system.enrolledCodes.count == 1)
        #expect(system.ran == ["systemctl enable --quiet hive-scout", "systemctl restart hive-scout"])
    }

    @Test("Running again with a new code and the same binary enrolls and reloads the running service, without a restart")
    func enrollAgain() throws {
        // Arrange
        try boot(.systemd, tools: ["useradd"])
        try install(code: Self.code)
        system.commands = []

        // Act
        try install(code: Self.code)

        // Assert
        #expect(system.enrolledCodes.count == 2)
        #expect(system.ran == ["systemctl enable --quiet hive-scout", "systemctl reload hive-scout"])
    }

    @Test("On Alpine without sudo, the OpenRC script and a doas rule are written, the rule checked before it's kept")
    func installsUnderOpenRCWithDoas() throws {
        // Arrange
        try boot(.openRC, tools: ["adduser", "addgroup", "doas"])
        try FileManager.default.createDirectory(at: server.root.appending(path: "etc/doas.d"), withIntermediateDirectories: true)

        // Act
        try install(sshUser: "deploy", code: Self.code)

        // Assert
        #expect(text(layout.openRCScript) == InitSystem.openRC.serviceFile(for: layout).text)
        #expect(try mode(layout.openRCScript) == 0o755)
        #expect(text(layout.doasRule) == ManagementRule.doas.text(for: try #require(SSHUserName("deploy")), binary: layout.binary))
        #expect(try mode(layout.doasRule) == 0o440)
        #expect(system.ran == [
            "addgroup -S hive-scout",
            "adduser -S -D -H -h /var/lib/hive-scout -s /bin/false -G hive-scout hive-scout",
            "doas -C \(layout.onDisk(layout.doasRule)).new",
            "rc-update add hive-scout default",
            "rc-service hive-scout restart",
        ])
    }

    @Test("A sudo rule that visudo refuses is left out, and nothing is put in its place")
    func sudoRuleRefused() throws {
        // Arrange
        try boot(.systemd, tools: ["useradd", "sudo", "visudo"])
        system.answers["visudo"] = CommandResult(status: 1, output: "syntax error")

        // Act
        let error = refusal(sshUser: "deploy", code: Self.code)

        // Assert
        #expect(error == .ruleRefused(output: "syntax error"))
        #expect(!FileManager.default.fileExists(atPath: layout.onDisk(layout.sudoRule)))
        #expect(!FileManager.default.fileExists(atPath: layout.onDisk(layout.sudoRule) + ".new"))
    }

    @Test("Install refuses, saying why, before changing anything")
    func refusals() throws {
        try boot(.systemd, tools: ["useradd"])
        let before = try everything()

        system.isRoot = false
        #expect(refusal(code: Self.code) == .notRoot)
        system.isRoot = true

        #expect(refusal() == .needsCode)
        #expect(InstallMessage.text(for: .needsCode).contains("needs an enrollment code"))

        let names = ["deploy user", "#1000", "ALL", "ROOT_USERS", "Defaults", "-deploy", "", "deploy\nroot", "deploy,root", "dé"]
        for name in names {
            #expect(refusal(sshUser: name, code: Self.code) == .sshUserNotAName(name), "\(name)")
        }
        #expect(refusal(sshUser: "nobody-here", code: Self.code) == .sshUserMissing("nobody-here"))
        #expect(refusal(sshUser: "deploy", code: Self.code) == .noSudoOrDoas)

        #expect(try everything() == before)
        #expect(system.commands.isEmpty)
        #expect(system.enrolledCodes.isEmpty)
    }

    @Test("An init system other than systemd or OpenRC is refused")
    func unknownInitSystem() throws {
        #expect(refusal(code: Self.code) == .unknownInitSystem)
        #expect(InstallMessage.text(for: .unknownInitSystem).contains("hive-scout run"))
    }

    @Test("A first install that can't enroll, as when no address can be reached, removes what it made")
    func enrollmentFails() throws {
        // Arrange
        try boot(.systemd, tools: ["useradd", "userdel", "groupdel"])
        let before = try everything()
        system.enrollSucceeds = false

        // Act
        let error = refusal(code: Self.code)

        // Assert
        #expect(error == .enrollmentFailed)
        #expect(try everything() == before)
        #expect(system.users["hive-scout"] == nil)
        #expect(!system.groups.contains("hive-scout"))
    }

    @Test("Installing on a /proc with hidepid says processes will be hidden")
    func hidepid() throws {
        // Arrange
        try boot(.systemd, tools: ["useradd"])
        try server.write("/proc/self/mountinfo", "22 1 0:21 / /proc rw,nosuid - proc proc rw,hidepid=invisible\n")

        // Act
        try install(code: Self.code)

        // Assert
        #expect(said.all.contains { $0.contains("hidepid") })
    }

    @Test("Uninstall removes the service, binary, rule, state folder and user, and stops the user's manager, leaving nothing behind")
    func uninstall() throws {
        // Arrange
        try boot(.systemd, tools: ["useradd", "userdel", "groupdel", "sudo", "visudo", "loginctl"])
        let before = try everything()
        try install(sshUser: "deploy", code: Self.code)
        let state = layout.onDisk(layout.stateDirectory)
        try FileManager.default.createDirectory(atPath: state + "/left/inside", withIntermediateDirectories: true)
        // A link inside is removed, never followed.
        try FileManager.default.createSymbolicLink(atPath: state + "/link", withDestinationPath: layout.onDisk("/etc"))
        system.commands = []

        // Act
        try UninstallWorkflow(layout: layout, system: system, say: { [said] in said.append($0) }).uninstall()

        // Assert
        #expect(try everything() == before)
        #expect(system.users["hive-scout"] == nil)
        #expect(!system.groups.contains("hive-scout"))
        #expect(system.ran == [
            "systemctl disable --now --quiet hive-scout",
            "systemctl daemon-reload",
            "loginctl disable-linger hive-scout",
            "systemctl stop user@500.service",
            "userdel hive-scout",
            "groupdel hive-scout",
        ])
    }
}
