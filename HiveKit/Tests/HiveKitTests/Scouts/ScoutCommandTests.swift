@testable import HiveKit
import Testing

struct ScoutCommandTests {
    private static let x86Hash = String(repeating: "a1", count: 32)
    private static let armHash = String(repeating: "b2", count: 32)
    private static let folder = "https://github.com/example/hive/releases/download/v2026.5/"
    private static let release = ScoutRelease(version: "0.2.0", downloadFolder: folder, sha256X86: x86Hash, sha256Arm: armHash)
    /// As long as a code with one short address.
    private static let code = "scout1:" + String(repeating: "Ab0-_", count: 23)
    private static let badCodes: [String] = {
        let appended: [String] = ["$(reboot)", "'", "\"", " x", "\nreboot", ";", "`", "é", "e\u{301}"].map { code + $0 }
        let others: [String] = [
            "scout2:" + code.dropFirst(7),
            " " + code,
            String(code.dropLast()),
            "scout1:" + String(repeating: "A", count: 2841),
            "",
        ]
        return appended + others
    }()

    @Test("The install command downloads the binary for the CPU, checks its hash, and passes the code on standard input")
    func install() throws {
        // Arrange
        let release = try #require(Self.release)

        // Act
        let x86 = ScoutCommand.install(release, for: .x86, code: Self.code)
        let arm = ScoutCommand.install(release, for: .arm, code: Self.code, sshUser: "deploy")

        // Assert
        #expect(x86 == """
        (set -e; d=$(mktemp -d); trap 'rm -rf "$d"' EXIT; cd "$d"
        u='\(Self.folder)hive-scout-linux-x86_64'
        curl -fsSLo hive-scout "$u" || wget -qO hive-scout "$u"
        echo '\(Self.x86Hash)  hive-scout' | sha256sum -c
        chmod 700 hive-scout
        echo '\(Self.code)' | ./hive-scout install)
        """)
        #expect(arm?.contains("u='\(Self.folder)hive-scout-linux-aarch64'") == true)
        #expect(arm?.contains("echo '\(Self.armHash)  hive-scout'") == true)
        #expect(arm?.hasSuffix("echo '\(Self.code)' | ./hive-scout install --ssh-user deploy)") == true)
    }

    @Test("The update command installs the release keeping the enrollment, with no code")
    func update() throws {
        // Act
        let command = ScoutCommand.update(try #require(Self.release), for: .x86)

        // Assert
        #expect(command.hasSuffix("\n./hive-scout install < /dev/null)"))
        #expect(!command.contains("scout1:"))
    }

    @Test(
        "A code holding anything outside base64url, or of the wrong length, gives no command",
        arguments: badCodes
    )
    func badCodeRefused(code: String) throws {
        // Act
        let command = ScoutCommand.install(try #require(Self.release), for: .x86, code: code)

        // Assert
        #expect(command == nil)
    }

    @Test("Codes at the shortest and longest lengths give a command")
    func codeLengths() throws {
        // Arrange
        let release = try #require(Self.release)

        // Act
        let shortest = ScoutCommand.install(release, for: .x86, code: "scout1:" + String(repeating: "A", count: 115))
        let longest = ScoutCommand.install(release, for: .x86, code: "scout1:" + String(repeating: "A", count: 2840))

        // Assert
        #expect(shortest != nil)
        #expect(longest != nil)
    }

    @Test(
        "A user name outside POSIX's portable pattern gives no command",
        arguments: [
            "$(id)", "de ploy", "dep'loy", "deploy\n", "-deploy", "", "dëploy", "deploy;id", String(repeating: "a", count: 33),
        ]
    )
    func badUserNameRefused(name: String) throws {
        // Act
        let command = ScoutCommand.install(try #require(Self.release), for: .x86, code: Self.code, sshUser: name)

        // Assert
        #expect(command == nil)
    }

    @Test(
        "User names in the portable pattern give a command",
        arguments: ["deploy", "web_1.backup-user", String(repeating: "a", count: 32)]
    )
    func portableUserNames(name: String) throws {
        // Act
        let command = ScoutCommand.install(try #require(Self.release), for: .x86, code: Self.code, sshUser: name)

        // Assert
        #expect(command?.hasSuffix("--ssh-user \(name))") == true)
    }

    @Test(
        "A release with a value missing or not as a release writes it is no release, so no command is built from it",
        arguments: [
            ("0.2.0", "", x86Hash),
            ("0.2.0", "http://github.com/example/hive/releases/download/v2026.5/", x86Hash),
            ("0.2.0", "https://example.com/it's/", x86Hash),
            ("0.2.0", "https://example.com/$(reboot)/", x86Hash),
            ("0.2.0", "https://example.com/download", x86Hash),
            ("0.2.0", folder, ""),
            ("0.2.0", folder, String(repeating: "A1", count: 32)),
            ("0.2.0", folder, x86Hash + "'"),
            ("", folder, x86Hash),
            ("0.2", folder, x86Hash),
        ]
    )
    func badRelease(version: String, folder: String, hash: String) {
        // Act
        let release = ScoutRelease(version: version, downloadFolder: folder, sha256X86: hash, sha256Arm: Self.armHash)

        // Assert
        #expect(release == nil)
    }
}
