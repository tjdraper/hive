import Foundation

/// The Scout release this build of Beekeeper knows: where its binaries are downloaded from and their
/// SHA-256s. Built into Beekeeper, so a Hive taken over by someone else can't point a server at a
/// binary of its own.
public struct ScoutRelease: Hashable, Sendable {
    public enum Platform: String, CaseIterable, Codable, Hashable, Sendable {
        case x86 = "x86_64"
        case arm = "aarch64"

        /// As `uname -m` prints it.
        public var cpu: String {
            rawValue
        }

        var fileName: String {
            "hive-scout-linux-\(rawValue)"
        }
    }

    public let version: String
    /// The release's download folder, ending in `/`.
    let downloadFolder: String
    let sha256: [Platform: String]

    /// Nil when any value is missing or isn't what a release writes, such as in a development build,
    /// which has nowhere to download from.
    public init?(version: String, downloadFolder: String, sha256X86: String, sha256Arm: String) {
        guard Self.isVersion(version), Self.isDownloadFolder(downloadFolder),
              [sha256X86, sha256Arm].allSatisfy(Self.isSHA256)
        else { return nil }
        self.version = version
        self.downloadFolder = downloadFolder
        sha256 = [.x86: sha256X86, .arm: sha256Arm]
    }

    private static func isVersion(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.count <= 6 && $0.allSatisfy(\.isASCIIDigit) }
    }

    /// Only characters that need no quoting in a URL, so it can't end the quotes it's put in.
    private static func isDownloadFolder(_ text: String) -> Bool {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/%")
        return text.hasPrefix("https://") && text.hasSuffix("/") && text.count <= 512 && text.allSatisfy(allowed.contains)
    }

    private static func isSHA256(_ text: String) -> Bool {
        text.count == 64 && text.allSatisfy { $0.isASCIIDigit || "abcdef".contains($0) }
    }
}

/// The commands to paste on a server as root, built by Beekeeper from its own `ScoutRelease` and
/// checked values, never from text Hive sent as it is, so a Hive taken over by someone else can't slip
/// a command of its own into what's run as root (§2).
public enum ScoutCommand {
    /// The `scout1:` prefix, then base64url of 82 bytes and one to eight addresses of 4 to 256 bytes each,
    /// as `EnrollmentCode` in `ScoutProtocol` writes it.
    static let codePrefix = "scout1:"
    static let shortestCode = 115
    static let longestCode = 2840
    /// `useradd`'s limit on most distributions.
    static let longestUserName = 32

    /// Downloads the binary for `platform` into a private temporary folder, stops unless its SHA-256
    /// matches, and installs it, enrolling with `code` read from standard input, so it never shows in
    /// `ps`. With `sshUser`, that user may run Scout's management command as root afterwards. Nil when
    /// the code or the name isn't what it should be.
    public static func install(
        _ release: ScoutRelease,
        for platform: ScoutRelease.Platform,
        code: String,
        sshUser: String? = nil
    ) -> String? {
        guard isCode(code) else { return nil }
        var install = "./hive-scout install"
        if let sshUser {
            guard isPortableUserName(sshUser) else { return nil }
            install += " --ssh-user \(sshUser)"
        }
        return download(release, for: platform, then: "echo '\(code)' | \(install)")
    }

    /// Replaces the installed binary with `release`'s and restarts Scout, keeping its enrollment.
    public static func update(_ release: ScoutRelease, for platform: ScoutRelease.Platform) -> String {
        download(release, for: platform, then: "./hive-scout install < /dev/null")
    }

    public static let uninstall = "/usr/local/bin/hive-scout uninstall"

    private static func download(_ release: ScoutRelease, for platform: ScoutRelease.Platform, then install: String) -> String {
        let hash = release.sha256[platform] ?? ""
        return """
        (set -e; d=$(mktemp -d); trap 'rm -rf "$d"' EXIT; cd "$d"
        u='\(release.downloadFolder)\(platform.fileName)'
        curl -fsSLo hive-scout "$u" || wget -qO hive-scout "$u"
        echo '\(hash)  hive-scout' | sha256sum -c
        chmod 700 hive-scout
        \(install))
        """
    }

    /// Checked as base64url within a code's length, so nothing in it means anything to a shell.
    public static func isCode(_ text: String) -> Bool {
        guard text.hasPrefix(codePrefix) else { return false }
        let body = text.dropFirst(codePrefix.count)
        return (shortestCode ... longestCode).contains(body.count)
            && body.allSatisfy { $0.isASCIILetter || $0.isASCIIDigit || $0 == "-" || $0 == "_" }
    }

    /// POSIX's portable user name pattern: letters, digits, `.`, `_` and `-`, not starting with `-`.
    /// Scout checks it again, and refuses names `sudo` would read as an alias or keyword too.
    static func isPortableUserName(_ text: String) -> Bool {
        guard let first = text.first, first != "-", text.count <= longestUserName else { return false }
        return text.allSatisfy { $0.isASCIILetter || $0.isASCIIDigit || $0 == "." || $0 == "_" || $0 == "-" }
    }
}

/// By byte, since comparing `Character`s follows Unicode's order, which puts some characters with
/// accents among the letters.
private extension Character {
    var isASCIIDigit: Bool {
        isASCII && asciiValue.map { (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains($0) } == true
    }

    var isASCIILetter: Bool {
        isASCII && asciiValue.map {
            (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains($0) || (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains($0)
        } == true
    }
}
