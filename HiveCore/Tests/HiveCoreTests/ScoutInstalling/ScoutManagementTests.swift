import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import ScoutProtocol
import Testing

/// A server answering Hive's probe with what it's told, and Scout answering each request with `answer`.
private struct FakeScoutServer: Sendable {
    var cpu = "x86_64"
    var access = "sudo"
    var installedVersion: String? = "0.1.0"
    var answer = ManagementResponse(outcome: .done, version: "0.2.0", platform: "linux-x86_64", message: "Done.")

    func respond(to command: String) -> ChildProcess.Result {
        guard command == ScoutProbe.command else {
            return ChildProcess.Result(status: 0, standardOutput: (try? JSONEncoder().encode(answer)) ?? Data(), standardError: Data())
        }
        var lines = ["system Linux", "cpu \(cpu)", "init systemd", "rule-tool yes", "access \(access)"]
        if let installedVersion {
            lines.append("installed yes")
            lines.append(#"status {"outcome":"done","version":"\#(installedVersion)","platform":"linux-\#(cpu)","message":""}"#)
        } else {
            lines.append("installed no")
        }
        return ChildProcess.Result(status: 0, standardOutput: Data((lines.joined(separator: "\n") + "\n").utf8), standardError: Data())
    }
}

struct ScoutManagementTests {
    private static let binary = Data("hive-scout 0.2.0 for linux-x86_64".utf8)

    private let carriedFolder: TemporaryDirectory
    private let fixture: APIFixture
    private let server: Server

    init() async throws {
        carriedFolder = try TemporaryDirectory()
        try Self.binary.write(to: carriedFolder.url.appending(path: "hive-scout-linux-x86_64"))
        let sha256 = Array(SHA256.hash(data: Self.binary))
        let statement = ReleaseStatement(version: ScoutVersion(0, 2, 0), platform: "linux-x86_64", sha256: sha256)
        // Hive checks only that the binary is the one the statement names; the server's Scout checks the signature.
        let file = statement.signedText + "signature \(Data(repeating: 7, count: 64).base64EncodedString())\n"
        try Data(file.utf8).write(to: carriedFolder.url.appending(path: "hive-scout-linux-x86_64.statement"))
        fixture = try APIFixture(scoutVersion: "0.2.0", scoutFolder: carriedFolder.url)
        try fixture.setAddressOptions()
        server = try await fixture.addServer()
        try await fixture.confirmHostKey(of: server)
    }

    private var sha256: String {
        SHA256.hash(data: Self.binary).map { String(format: "%02x", $0) }.joined()
    }

    private func serve(_ fake: FakeScoutServer) {
        fixture.ssh.answer { command, _ in fake.respond(to: command) }
    }

    private func perform(_ action: ScoutAction, confirmed: Bool = false) async throws -> APIAnswer {
        let path = HiveEndpoint.scoutAction(onServer: server.id)
        let request = ScoutActionRequest(action: action)
        return try await confirmed ? fixture.sendConfirmed(.post, path, json: request) : fixture.send(.post, path, json: request)
    }

    /// Oldest first.
    private func scoutEvents() throws -> [ScoutChange] {
        try fixture.auditEvents().reversed().compactMap { event in
            if case .scout(_, _, let change) = event { return change }
            return nil
        }
    }

    /// The request line Scout was last sent, and what came after it.
    private func lastSent() throws -> (request: ManagementRequest, rest: Data) {
        let last: Data? = fixture.ssh.inputs.last.flatMap(\.self)
        let input = try #require(last)
        let newline = try #require(input.firstIndex(of: UInt8(ascii: "\n")))
        return (try JSONDecoder().decode(ManagementRequest.self, from: input[..<newline]), Data(input[(newline + 1)...]))
    }

    @Test("Checking runs only the probe, and says what Hive can do")
    func check() async throws {
        // Arrange
        serve(FakeScoutServer(access: "sudo-rule"))

        // Act
        let result = try await fixture.send(.post, HiveEndpoint.scoutCheck(onServer: server.id)).decoded(as: ScoutCheckResult.self)

        // Assert
        let check = try #require(result.check)
        #expect(check.access == .sudoRule)
        #expect(check.installedVersion == "0.1.0")
        #expect(check.sshUser == "backup")
        #expect(fixture.ssh.ran.map(\.command) == [ScoutProbe.command])
    }

    @Test("Install and enroll again without confirmation are refused before Hive connects, opening no window")
    func needConfirmation() async throws {
        // Arrange
        serve(FakeScoutServer(installedVersion: nil))
        let before = try fixture.auditEvents()

        // Act, Assert
        for action in [ScoutAction.install, .enrollAgain] {
            let answer = try await perform(action)
            #expect(answer.status == .preconditionRequired)
            #expect(try answer.confirmationReasons == [.enrollmentWindowOpened])
        }
        #expect(fixture.ssh.ran.isEmpty)
        #expect(try fixture.auditEvents() == before)
    }

    @Test("Install opens a window and streams Hive.app's binary for the server's CPU with the code, to be run as root")
    func install() async throws {
        // Arrange
        serve(FakeScoutServer(installedVersion: nil))

        // Act
        let result = try await perform(.install, confirmed: true).decoded(as: ScoutActionResult.self)

        // Assert
        #expect(result.outcome == .done)
        #expect(result.version == "0.2.0")
        let ran = fixture.ssh.ran.map(\.command)
        #expect(ran == [ScoutProbe.command, ScoutManagementCommand.installCarried(sha256: sha256, through: .sudo)])
        let (request, binary) = try lastSent()
        #expect(request.request == .install)
        let code = try #require(EnrollmentCode(text: request.code ?? ""))
        #expect(code.serverID == server.id)
        #expect(binary == Self.binary)
        #expect(try scoutEvents() == [.enrollmentWindowOpened, .installed(version: "0.2.0")])
    }

    @Test("Install is refused without root, or where Scout is already, opening no window")
    func installRefused() async throws {
        for (fake, problem) in [
            (FakeScoutServer(access: "sudo-rule", installedVersion: nil), ScoutActionProblem.noRootAccess),
            (FakeScoutServer(access: "none", installedVersion: nil), .noRootAccess),
            (FakeScoutServer(access: "root"), .alreadyInstalled),
            (FakeScoutServer(cpu: "armv7l", installedVersion: nil), .unsupported),
        ] {
            serve(fake)
            let result = try await perform(.install, confirmed: true).decoded(as: ScoutActionResult.self)
            #expect(result.outcome == .refused)
            #expect(result.problem == problem)
        }
        #expect(fixture.ssh.ran.allSatisfy { $0.command == ScoutProbe.command })
        #expect(try scoutEvents().isEmpty)
    }

    @Test("When Scout refuses an install, its message is shown, the window is closed, and nothing is recorded as installed")
    func installRefusedByScout() async throws {
        // Arrange
        var fake = FakeScoutServer(installedVersion: nil)
        fake.answer = ManagementResponse(outcome: .refused, version: "0.2.0", platform: "linux-x86_64", message: "Scout couldn't enroll.")
        serve(fake)

        // Act
        let result = try await perform(.install, confirmed: true).decoded(as: ScoutActionResult.self)

        // Assert
        #expect(result.outcome == .refused)
        #expect(result.message == "Scout couldn't enroll.")
        #expect(try scoutEvents() == [.enrollmentWindowOpened, .enrollmentWindowClosed])
    }

    @Test("Update sends the statement and binary through Scout's rule, and is recorded")
    func update() async throws {
        // Arrange
        serve(FakeScoutServer(access: "doas-rule"))

        // Act
        let result = try await perform(.update).decoded(as: ScoutActionResult.self)

        // Assert
        #expect(result.outcome == .done)
        #expect(fixture.ssh.ran.last?.command == "'doas' '-n' '/usr/local/bin/hive-scout' 'manage'")
        let (request, binary) = try lastSent()
        #expect(request.request == .update)
        #expect(request.binaryLength == Self.binary.count)
        #expect(request.statement?.hasPrefix("hive-scout release statement\nversion 0.2.0\nplatform linux-x86_64\n") == true)
        #expect(binary == Self.binary)
        #expect(try scoutEvents() == [.updated(version: "0.2.0")])
    }

    @Test("Hive never offers a Scout the same or an older version, nor one for another CPU")
    func updateRefused() async throws {
        for (fake, problem) in [
            (FakeScoutServer(installedVersion: "0.2.0"), ScoutActionProblem.upToDate),
            (FakeScoutServer(installedVersion: "0.3.0"), .upToDate),
            (FakeScoutServer(cpu: "aarch64"), .noCarriedRelease),
            (FakeScoutServer(installedVersion: nil), .notInstalled),
            (FakeScoutServer(access: "none"), .noRootAccess),
        ] {
            serve(fake)
            let result = try await perform(.update).decoded(as: ScoutActionResult.self)
            #expect(result.problem == problem)
        }
        #expect(fixture.ssh.ran.allSatisfy { $0.command == ScoutProbe.command })
    }

    @Test("Enrolling again sends a new code to the installed Scout's manage")
    func enrollAgain() async throws {
        // Arrange
        serve(FakeScoutServer(access: "sudo-rule"))

        // Act
        let result = try await perform(.enrollAgain, confirmed: true).decoded(as: ScoutActionResult.self)

        // Assert
        #expect(result.outcome == .done)
        #expect(fixture.ssh.ran.last?.command == ScoutManagementCommand.manage(through: .sudoRule))
        let (request, rest) = try lastSent()
        #expect(request.request == .install)
        #expect(EnrollmentCode(text: request.code ?? "")?.serverID == server.id)
        #expect(rest.isEmpty)
    }

    @Test("New addresses are the Hive's address options")
    func sendAddresses() async throws {
        // Arrange
        serve(FakeScoutServer(access: "root"))

        // Act
        let result = try await perform(.sendAddresses).decoded(as: ScoutActionResult.self)

        // Assert
        #expect(result.outcome == .done)
        let (request, _) = try lastSent()
        #expect(request.addresses == [
            EnrollmentCode.Address(host: "studio.tail0000.ts.net", port: APIFixture.defaultPort),
            EnrollmentCode.Address(host: "hive.example.com", port: 44830),
        ])
        #expect(try scoutEvents() == [.addressesSent])
    }

    @Test("Uninstalling removes the server's metrics, so its Scout can't sign in again")
    func uninstall() async throws {
        // Arrange
        _ = try await fixture.enrollScout(for: server)
        serve(FakeScoutServer(access: "sudo-rule"))

        // Act
        let result = try await perform(.uninstall).decoded(as: ScoutActionResult.self)

        // Assert
        #expect(result.outcome == .done)
        let (request, _) = try lastSent()
        #expect(request.request == .uninstall)
        #expect(try fixture.api.scouts.scout(forServer: server.id) == nil)
        #expect(try fixture.api.scouts.hasMetrics(server.id) == false)
        #expect(try scoutEvents().suffix(2) == [.uninstalled, .removed])
    }

    @Test("A Scout failing part way is recorded, and its message shown")
    func failedPartWay() async throws {
        // Arrange
        var fake = FakeScoutServer()
        fake.answer = ManagementResponse(outcome: .failed, version: "0.2.0", platform: "linux-x86_64", message: "The service didn't start.")
        serve(fake)

        // Act
        let result = try await perform(.update).decoded(as: ScoutActionResult.self)

        // Assert
        #expect(result.outcome == .failed)
        #expect(result.message == "The service didn't start.")
        #expect(try scoutEvents() == [.actionFailed(.update)])
    }

    @Test("Nothing a server or its Scout says goes into a command Hive runs")
    func nothingFromServerRuns() async throws {
        // Arrange
        let hostile = "$(reboot)'; reboot; '"
        fixture.ssh.answer { command, _ in
            guard command == ScoutProbe.command else {
                let answer = #"{"outcome":"done","version":"\#(hostile)","platform":"\#(hostile)","message":"\#(hostile)"}"#
                return ChildProcess.Result(status: 0, standardOutput: Data(answer.utf8), standardError: Data(hostile.utf8))
            }
            let status = #"{"outcome":"done","version":"0.1.0","platform":"linux-x86_64","message":"\#(hostile)"}"#
            let output = "system Linux\ncpu x86_64\ninit systemd\n\(hostile) \(hostile)\naccess sudo\ninstalled yes\nstatus \(status)\n"
            return ChildProcess.Result(status: 0, standardOutput: Data(output.utf8), standardError: Data(hostile.utf8))
        }

        // Act
        for action in ScoutAction.allCases {
            _ = try await perform(action, confirmed: true)
        }
        _ = try await fixture.send(.post, HiveEndpoint.scoutCheck(onServer: server.id))

        // Assert
        let built = Set([
            ScoutProbe.command,
            ScoutManagementCommand.manage(through: .sudo),
            ScoutManagementCommand.installCarried(sha256: sha256, through: .sudo),
        ].compactMap(\.self))
        #expect(!fixture.ssh.ran.isEmpty)
        #expect(fixture.ssh.ran.allSatisfy { built.contains($0.command) && !$0.command.contains("reboot") })
    }

    @Test("A server Hive can't reach is reported, with nothing changed")
    func unreachable() async throws {
        // Arrange
        let refused = "ssh: connect to host web.example.com port 22: Connection refused"
        fixture.ssh.setResult(status: SSHFailureReader.sshErrorStatus, standardError: refused)

        // Act
        let result = try await perform(.update).decoded(as: ScoutActionResult.self)

        // Assert
        #expect(result.outcome == .refused)
        #expect(result.failure == .unreachable)
        #expect(fixture.ssh.ran.count == 1)
    }
}
