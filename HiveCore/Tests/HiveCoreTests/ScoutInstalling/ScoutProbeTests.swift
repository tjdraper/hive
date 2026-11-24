import Foundation
@testable import HiveCore
import HiveKit
import Testing

/// Runs the probe's script with `sh` on this Mac, among stand-ins for a server's `uname`, `id`,
/// `sudo`, `doas` and Scout, so what's tested is the script a server runs as well as how its answer is read.
struct ScoutProbeTests {
    private enum Sudo {
        case passwordless
        case asksForPassword
        /// Allows only Scout's `manage`, as A4's rule does.
        case scoutRule
    }

    private let folder: TemporaryDirectory

    init() throws {
        folder = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: folder.url.appending(path: "bin"), withIntermediateDirectories: true)
        for tool in ["tail", "env", "cat", "true"] {
            try FileManager.default.createSymbolicLink(atPath: folder.path("bin/\(tool)"), withDestinationPath: "/usr/bin/\(tool)")
        }
        try tool("uname", #"case "$1" in -s) echo Linux;; -m) echo x86_64;; esac"#)
    }

    private var binary: String {
        folder.path("hive-scout")
    }

    private func tool(_ name: String, _ body: String) throws {
        let path = name == "hive-scout" ? binary : folder.path("bin/\(name)")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: URL(filePath: path))
        chmod(path, 0o755)
    }

    private func server(uid: Int = 1000, sudo: Sudo? = nil, doas: Sudo? = nil, installed: Bool = true) throws {
        try tool("id", "echo \(uid)")
        if let sudo { try tool("sudo", script(for: sudo, deniedSaying: "sudo: a password is required")) }
        if let doas { try tool("doas", script(for: doas, deniedSaying: "doas: Authentication failed")) }
        if installed {
            let answer = #"{"outcome":"done","version":"0.1.0","platform":"linux-x86_64","message":"Scout 0.1.0 for linux-x86_64."}"#
            try tool("hive-scout", "read request; echo '\(answer)'")
        }
    }

    private func script(for sudo: Sudo, deniedSaying denial: String) -> String {
        switch sudo {
        case .passwordless:
            #"[ "$1" = -n ] && shift; exec "$@""#
        case .asksForPassword:
            "echo '\(denial)' >&2; exit 1"
        case .scoutRule:
            """
            if [ "$1" = -n ] && [ "$2" = "\(binary)" ] && [ "$3" = manage ] && [ $# -eq 3 ]; then shift; exec "$@"; fi
            echo '\(denial)' >&2; exit 1
            """
        }
    }

    private func probe() throws -> ScoutServerCheck? {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", ScoutProbe.script(binary: binary)]
        process.environment = ["PATH": folder.path("bin")]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ScoutProbe.check(in: data, sshUser: "deploy")
    }

    @Test("Signed in as root, Hive has root, and asks Scout its version directly")
    func root() throws {
        try server(uid: 0)

        let check = try #require(try probe())

        #expect(check.access == .root)
        #expect(check.installedVersion == "0.1.0")
        #expect(check.platform == .x86)
    }

    @Test("Passwordless sudo, or doas, gives root")
    func passwordless() throws {
        try server(sudo: .passwordless)
        #expect(try probe()?.access == .sudo)

        try FileManager.default.removeItem(atPath: folder.path("bin/sudo"))
        try server(doas: .passwordless)
        let check = try #require(try probe())
        #expect(check.access == .doas)
        #expect(check.installedVersion == "0.1.0")
    }

    @Test("Scout's sudo or doas rule is found by asking Scout its version through it")
    func scoutRule() throws {
        try server(sudo: .scoutRule)
        let check = try #require(try probe())
        #expect(check.access == .sudoRule)
        #expect(check.installedVersion == "0.1.0")

        try FileManager.default.removeItem(atPath: folder.path("bin/sudo"))
        try server(doas: .scoutRule)
        #expect(try probe()?.access == .doasRule)
    }

    @Test("sudo or doas asking for a password counts as no access, and Hive never answers it")
    func asksForPassword() throws {
        try server(sudo: .asksForPassword, doas: .asksForPassword)

        let check = try #require(try probe())

        #expect(check.access == ScoutRootAccess.none)
        #expect(check.hasSudoOrDoas)
        #expect(check.isInstalled)
        #expect(check.installedVersion == nil)
    }

    @Test("Without sudo or doas, or Scout, there's no access, and it says which is missing")
    func nothing() throws {
        try server(installed: false)

        let check = try #require(try probe())

        #expect(check.access == ScoutRootAccess.none)
        #expect(!check.hasSudoOrDoas)
        #expect(!check.isInstalled)
    }

    @Test("A system, CPU or init system Scout doesn't support is what's in the way")
    func obstacles() {
        func obstacle(_ output: String) -> ScoutObstacle?? {
            ScoutProbe.check(in: Data(output.utf8), sshUser: "deploy").map(\.obstacle)
        }
        #expect(obstacle("system Linux\ncpu aarch64\ninit openrc\naccess root\n") == .some(nil))
        #expect(obstacle("system Darwin\ncpu arm64\ninit other\naccess root\n") == .notLinux)
        #expect(obstacle("system Linux\ncpu armv7l\ninit systemd\naccess root\n") == .unsupportedCPU)
        #expect(obstacle("system Linux\ncpu x86_64\ninit other\naccess root\n") == .unsupportedInitSystem)
        #expect(obstacle("system Linux\ncpu x86_64\ninit systemd\naccess everything\n") == nil)
        #expect(obstacle("Welcome to the server!\n") == nil)
    }

    @Test("A version is kept only as a release writes it, from a Scout for the server's own CPU")
    func versions() {
        func version(_ status: String) -> String? {
            let output = "system Linux\ncpu x86_64\ninit systemd\naccess sudo-rule\ninstalled yes\nstatus \(status)\n"
            return ScoutProbe.check(in: Data(output.utf8), sshUser: "deploy")?.installedVersion
        }
        #expect(version(#"{"outcome":"done","version":"0.2.0","platform":"linux-x86_64","message":""}"#) == "0.2.0")
        #expect(version(#"{"outcome":"done","version":"0.2.0","platform":"linux-aarch64","message":""}"#) == nil)
        #expect(version(#"{"outcome":"done","version":"0.2.0; reboot","platform":"linux-x86_64","message":""}"#) == nil)
        #expect(version(#"{"outcome":"refused","version":"0.2.0","platform":"linux-x86_64","message":""}"#) == nil)
        #expect(version("") == nil)
    }
}
