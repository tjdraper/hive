import Foundation
import HiveKit
import ScoutProtocol

/// Every command Hive runs on a server to act on Scout is built here, from Hive's own words and the
/// hash of a binary Hive.app carries. Nothing a server or its Scout said goes into one: what Hive sends
/// Scout, such as an enrollment code, goes on standard input.
enum ScoutManagementCommand {
    /// Where Scout installs itself, and the only command its `sudo` and `doas` rules allow, with `manage`.
    static let binary = "/usr/local/bin/hive-scout"

    /// Runs the installed Scout's `manage` as root, which reads one request from standard input. Nil
    /// without access to it.
    static func manage(through access: ScoutRootAccess) -> String? {
        rootPrefix(for: access).map { RemoteCommandLine.line($0 + [binary, "manage"]) }
    }

    /// Takes the request line, then the binary, from standard input: keeps the binary in a private
    /// temporary folder, checks it's whole, and hands the request to its `manage` as root. `read` takes
    /// the line a byte at a time, so the binary is left whole for `cat`. The temporary folder goes
    /// either way. Nil without root.
    static func installCarried(sha256: String, through access: ScoutRootAccess) -> String? {
        guard access.canInstall, let prefix = rootPrefix(for: access), isSHA256(sha256) else { return nil }
        let run = (prefix + ["\"$d/hive-scout\"", "manage"]).joined(separator: " ")
        let script = """
            set -e
            d=$(mktemp -d)
            trap 'rm -rf "$d"' EXIT
            IFS= read -r request
            cat > "$d/hive-scout"
            (cd "$d" && echo '\(sha256)  hive-scout' | sha256sum -c >/dev/null)
            chmod 700 "$d/hive-scout"
            printf '%s\\n' "$request" | \(run)
            """
        return RemoteCommandLine.line(["sh", "-c", script])
    }

    /// The request line, then the binary: for an update, as `manage` reads them, and for
    /// `installCarried`, the binary to install.
    static func input(_ request: ManagementRequest, binary: Data? = nil) throws -> Data {
        try JSONEncoder().encode(request) + Data("\n".utf8) + (binary ?? Data())
    }

    private static func rootPrefix(for access: ScoutRootAccess) -> [String]? {
        switch access {
        case .root: []
        case .sudo, .sudoRule: ["sudo", "-n"]
        case .doas, .doasRule: ["doas", "-n"]
        case .none: nil
        }
    }

    private static func isSHA256(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy {
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains($0)
        }
    }
}
