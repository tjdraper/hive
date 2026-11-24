import Foundation
import HiveKit
import ScoutProtocol

/// What Hive runs to find out what it can do about Scout on a server, and reads its answer. The script
/// changes nothing and takes nothing from outside Hive. `-n` keeps `sudo` and `doas` from asking for a
/// password, so asking counts as no access. Asking the installed Scout its version through `sudo -n`
/// or `doas -n` also proves Scout's rule works, without reading `sudo -l`, whose output varies by
/// version and language.
enum ScoutProbe {
    /// `binary` is Scout's installed path, which tests move.
    static func script(binary: String = ScoutManagementCommand.binary) -> String {
        """
        b=\(binary)
        r='{"request":"status"}'
        echo "system $(uname -s)"
        echo "cpu $(uname -m)"
        if [ -d /run/systemd/system ]; then echo "init systemd"
        elif [ -d /run/openrc ]; then echo "init openrc"
        else echo "init other"; fi
        has() { command -v "$1" >/dev/null 2>&1; }
        if has sudo || has doas; then echo "rule-tool yes"; else echo "rule-tool no"; fi
        if [ -x "$b" ]; then echo "installed yes"; else echo "installed no"; fi
        status() { echo "status $(echo "$r" | "$@" "$b" manage 2>/dev/null | tail -n 1)"; }
        if [ "$(id -u)" = 0 ]; then echo "access root"; [ -x "$b" ] && status env; exit 0; fi
        if has sudo && sudo -n true >/dev/null 2>&1; then echo "access sudo"; [ -x "$b" ] && status sudo -n; exit 0; fi
        if has doas && doas -n true >/dev/null 2>&1; then echo "access doas"; [ -x "$b" ] && status doas -n; exit 0; fi
        if [ -x "$b" ] && has sudo && o=$(echo "$r" | sudo -n "$b" manage 2>/dev/null | tail -n 1) && [ -n "$o" ]; then
            echo "access sudo-rule"; echo "status $o"; exit 0
        fi
        if [ -x "$b" ] && has doas && o=$(echo "$r" | doas -n "$b" manage 2>/dev/null | tail -n 1) && [ -n "$o" ]; then
            echo "access doas-rule"; echo "status $o"; exit 0
        fi
        echo "access none"
        """
    }

    static var command: String {
        RemoteCommandLine.line(["sh", "-c", script()])
    }

    /// Nil for output that isn't what the script writes. Only what it recognizes is kept, so nothing
    /// else the server says goes any further.
    static func check(in output: Data, sshUser: String) -> ScoutServerCheck? {
        guard let text = String(bytes: output, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard let key = parts.first, values[String(key)] == nil else { continue }
            values[String(key)] = parts.count == 2 ? String(parts[1]) : ""
        }
        guard let system = values["system"], let cpu = values["cpu"], let initSystem = values["init"],
              let access = values["access"].flatMap(access(named:))
        else { return nil }

        let platform = Self.platform(cpu: cpu)
        let obstacle: ScoutObstacle? = if system != "Linux" {
            .notLinux
        } else if platform == nil {
            .unsupportedCPU
        } else if !["systemd", "openrc"].contains(initSystem) {
            .unsupportedInitSystem
        } else {
            nil
        }
        return ScoutServerCheck(
            sshUser: sshUser,
            platform: platform,
            access: access,
            hasSudoOrDoas: values["rule-tool"] == "yes",
            installedVersion: values["status"].flatMap { installedVersion(in: $0, platform: platform) },
            isInstalled: values["installed"] == "yes",
            obstacle: obstacle
        )
    }

    /// As `uname -m` prints it. Some kernels call 64-bit ARM `arm64`.
    static func platform(cpu: String) -> ScoutRelease.Platform? {
        switch cpu {
        case "x86_64", "amd64": .x86
        case "aarch64", "arm64": .arm
        default: nil
        }
    }

    private static func access(named name: String) -> ScoutRootAccess? {
        switch name {
        case "root": .root
        case "sudo": .sudo
        case "doas": .doas
        case "sudo-rule": .sudoRule
        case "doas-rule": .doasRule
        case "none": ScoutRootAccess.none
        default: nil
        }
    }

    /// Only a version a release could have, from a status Scout answered for the server's own CPU.
    private static func installedVersion(in line: String, platform: ScoutRelease.Platform?) -> String? {
        guard let response = try? JSONDecoder().decode(ManagementResponse.self, from: Data(line.utf8)),
              response.outcome == .done,
              let platform, response.platform == "linux-\(platform.cpu)",
              let version = ScoutVersion(parsing: response.version)
        else { return nil }
        return version.description
    }
}
