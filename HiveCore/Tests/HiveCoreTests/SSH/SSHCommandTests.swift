import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct SSHCommandTests {
    private static let directory = SSHRunDirectory(
        url: URL(filePath: "/private/var/folders/xy/T/hive-ssh.abc123", directoryHint: .isDirectory)
    )

    static let targets = [
        target(ServerConnection(host: "web.example.com", user: "root")),
        target(ServerConnection(host: "100.64.0.9", port: 2222, user: "backup")),
        target(ServerConnection(host: "fd7a:115c:a1e0::9", port: 22, user: "hive_backup")),
    ]

    private static func target(_ connection: ServerConnection) -> SSHTarget {
        SSHTarget(serverID: UUID(), connection: connection, hostKey: ConfigurationSamples.hostKey, key: SSHKeyPair())
    }

    /// Each `-o` option's value, by name.
    private static func options(in arguments: [String]) -> [String: [String]] {
        var options: [String: [String]] = [:]
        for (index, argument) in arguments.enumerated() where argument == "-o" && index + 1 < arguments.count {
            let parts = arguments[index + 1].split(separator: "=", maxSplits: 1).map(String.init)
            options[parts[0], default: []].append(parts.count > 1 ? parts[1] : "")
        }
        return options
    }

    @Test("Every command checks the host key strictly against Hive's own known_hosts, under the server's alias", arguments: targets)
    func checksHostKey(target: SSHTarget) {
        // Act
        let options = Self.options(in: SSHCommand.arguments(for: target, in: Self.directory, remoteCommand: "true"))

        // Assert
        #expect(options["StrictHostKeyChecking"] == ["yes"])
        #expect(options["UserKnownHostsFile"] == [Self.directory.knownHosts.fileSystemPath])
        #expect(options["GlobalKnownHostsFile"] == ["/dev/null"])
        #expect(options["HostKeyAlias"] == [target.serverID.uuidString.lowercased()])
        #expect(options["UpdateHostKeys"] == ["no"])
        #expect(options["CheckHostIP"] == ["no"])
    }

    @Test("Every command uses only Hive's key, through its own agent, and never asks for a password", arguments: targets)
    func usesOnlyHiveKey(target: SSHTarget) {
        // Act
        let options = Self.options(in: SSHCommand.arguments(for: target, in: Self.directory, remoteCommand: "true"))

        // Assert
        #expect(options["BatchMode"] == ["yes"])
        #expect(options["IdentitiesOnly"] == ["yes"])
        #expect(options["IdentityFile"] == [Self.directory.identity.fileSystemPath])
        #expect(options["IdentityAgent"] == [Self.directory.agentSocket.fileSystemPath])
        #expect(options["PasswordAuthentication"] == ["no"])
        #expect(options["KbdInteractiveAuthentication"] == ["no"])
        #expect(options["ForwardAgent"] == ["no"])
    }

    @Test("Every command ignores the user's own config, and ends a slow or stalled connection", arguments: targets)
    func ignoresConfigAndEndsStalls(target: SSHTarget) {
        // Act
        let arguments = SSHCommand.arguments(for: target, in: Self.directory, remoteCommand: "true")
        let options = Self.options(in: arguments)

        // Assert
        #expect(Array(arguments.prefix(2)) == ["-F", "/dev/null"])
        #expect(options["ConnectTimeout"] == ["15"])
        #expect(options["ServerAliveInterval"] == ["15"])
        #expect(options["ServerAliveCountMax"] == ["4"])
        #expect(options["ControlMaster"] == ["no"])
    }

    @Test("Each option is given once, and none ever loosens host key checking", arguments: targets)
    func neverLoosens(target: SSHTarget) {
        // Act
        let arguments = SSHCommand.arguments(for: target, in: Self.directory, remoteCommand: "true")
        let options = Self.options(in: arguments)

        // Assert
        #expect(options.values.allSatisfy { $0.count == 1 })
        for argument in arguments {
            let lowered = argument.lowercased()
            #expect(!lowered.contains("stricthostkeychecking=no"))
            #expect(!lowered.contains("stricthostkeychecking=off"))
            #expect(!lowered.contains("stricthostkeychecking=accept-new"))
            #expect(!lowered.contains("userknownhostsfile=/dev/null"))
        }
    }

    @Test("The port, user and host come last, with the host after --, then the command", arguments: targets)
    func endsWithDestination(target: SSHTarget) {
        // Act
        let arguments = SSHCommand.arguments(for: target, in: Self.directory, remoteCommand: "true")

        // Assert
        #expect(Array(arguments.suffix(7)) == [
            "-p", String(target.connection.port), "-l", target.connection.user, "--", target.connection.host, "true",
        ])
    }

    @Test("known_hosts holds only the server's confirmed key, under its alias")
    func knownHostsHoldsOneKey() throws {
        // Arrange
        let target = try #require(Self.targets.first)

        // Act
        let contents = KnownHostsFile.contents(for: target)

        // Assert
        #expect(contents == "\(target.serverID.uuidString.lowercased()) \(ConfigurationSamples.hostKey.line)\n")
    }
}

extension SSHTarget: CustomTestStringConvertible {
    public var testDescription: String {
        "\(connection.user)@\(connection.host):\(connection.port)"
    }
}
