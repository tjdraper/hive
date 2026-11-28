@testable import hive_scout
import ScoutCore
import Testing

struct ScoutCommandTests {
    private static let pinHex = String(repeating: "ab", count: 32)

    @Test("Sample and watch are read, with or without a Hive to connect to")
    func commands() throws {
        #expect(ScoutCommand(arguments: ["sample"]) == .sample)
        #expect(ScoutCommand(arguments: ["watch"]) == .watch(nil))

        let watch = ScoutCommand(arguments: ["watch", "--pin", Self.pinHex, "--tls", "100.64.0.1:4484"])
        let pin = try #require(HiveKeyPin(hex: Self.pinHex))
        #expect(watch == .watch(.init(address: HiveAddress(host: "100.64.0.1", port: 4484), pin: pin)))
    }

    @Test("A connection to Hive is refused without a pin to check it against")
    func tlsWithoutPin() {
        #expect(ScoutCommand(arguments: ["watch", "--tls", "100.64.0.1:4484"]) == nil)
        #expect(ScoutCommand(arguments: ["watch", "--tls", "100.64.0.1:4484", "--tls", "100.64.0.2:4484"]) == nil)
        #expect(ScoutCommand(arguments: ["watch", "--tls", "100.64.0.1:4484", "--pin", "not-a-pin"]) == nil)
    }

    @Test("Enroll reads its code from standard input, and takes only a state folder as an argument")
    func enroll() {
        #expect(ScoutCommand(arguments: ["enroll"]) == .enroll(stateDirectory: InstallLayout.server.stateDirectory))
        #expect(ScoutCommand(arguments: ["enroll", "--state-directory", "/tmp/scout"]) == .enroll(stateDirectory: "/tmp/scout"))
    }

    @Test("Addresses are read from standard input, and only a state folder is taken as an argument")
    func addresses() {
        #expect(ScoutCommand(arguments: ["addresses"]) == .addresses(stateDirectory: InstallLayout.server.stateDirectory))
        #expect(ScoutCommand(arguments: ["addresses", "--state-directory", "/tmp/scout"]) == .addresses(stateDirectory: "/tmp/scout"))
        #expect(ScoutCommand(arguments: ["addresses", "hive.example.com:4483"]) == nil)
    }

    @Test("A code given as an argument is refused, so it never shows in `ps` or the journal")
    func enrollRefusesCodeArgument() {
        #expect(ScoutCommand(arguments: ["enroll", "scout1:AQIDBAUG"]) == nil)
        #expect(ScoutCommand(arguments: ["enroll", "--code", "scout1:AQIDBAUG"]) == nil)
        #expect(ScoutCommand(arguments: ["enroll", "--state-directory", "relative/folder"]) == nil)
        #expect(ScoutCommand(arguments: ["enroll", "--state-directory", "/tmp/scout", "scout1:AQIDBAUG"]) == nil)
    }

    @Test("Run, send and status take their folders as absolute paths, each at most once")
    func runAndStatus() {
        let layout = InstallLayout.server
        #expect(ScoutCommand(arguments: ["run"]) == .run(stateDirectory: layout.stateDirectory, runtimeDirectory: layout.runtimeDirectory))
        #expect(
            ScoutCommand(arguments: ["send", "--state-directory", "/tmp/state"])
                == .send(stateDirectory: "/tmp/state", runtimeDirectory: layout.runtimeDirectory)
        )
        #expect(
            ScoutCommand(arguments: ["run", "--runtime-directory", "/tmp/run", "--state-directory", "/tmp/state"])
                == .run(stateDirectory: "/tmp/state", runtimeDirectory: "/tmp/run")
        )
        #expect(ScoutCommand(arguments: ["status"]) == .status(runtimeDirectory: layout.runtimeDirectory))
        #expect(ScoutCommand(arguments: ["status", "--runtime-directory", "/tmp/run"]) == .status(runtimeDirectory: "/tmp/run"))

        #expect(ScoutCommand(arguments: ["run", "--state-directory", "relative"]) == nil)
        #expect(ScoutCommand(arguments: ["run", "--state-directory", "/a", "--state-directory", "/b"]) == nil)
        #expect(ScoutCommand(arguments: ["status", "--state-directory", "/tmp/state"]) == nil)
        #expect(ScoutCommand(arguments: ["run", "--state-directory"]) == nil)
        #expect(ScoutCommand(arguments: ["send", "--state-directory", "relative"]) == nil)
    }

    @Test("Install takes only the SSH user's name, reading the code from standard input, and uninstall takes nothing")
    func installAndUninstall() {
        #expect(ScoutCommand(arguments: ["install"]) == .install(sshUser: nil))
        #expect(ScoutCommand(arguments: ["install", "--ssh-user", "deploy"]) == .install(sshUser: "deploy"))
        #expect(ScoutCommand(arguments: ["uninstall"]) == .uninstall)

        #expect(ScoutCommand(arguments: ["install", "scout1:AQIDBAUG"]) == nil)
        #expect(ScoutCommand(arguments: ["install", "--ssh-user", "deploy", "scout1:AQIDBAUG"]) == nil)
        #expect(ScoutCommand(arguments: ["install", "--code", "scout1:AQIDBAUG"]) == nil)
        #expect(ScoutCommand(arguments: ["uninstall", "--ssh-user", "deploy"]) == nil)
    }

    @Test("Manage takes no arguments at all, so Scout's sudo and doas rules need to allow none")
    func manage() {
        #expect(ScoutCommand(arguments: ["manage"]) == .manage)

        #expect(ScoutCommand(arguments: ["manage", "update"]) == nil)
        #expect(ScoutCommand(arguments: ["manage", ""]) == nil)
        #expect(ScoutCommand(arguments: ["manage", "--state-directory", "/tmp/scout"]) == nil)
        #expect(ScoutCommand(arguments: ["manage", "--ssh-user", "deploy"]) == nil)
    }

    @Test("Unknown commands and extra arguments are refused")
    func unknown() {
        #expect(ScoutCommand(arguments: []) == nil)
        #expect(ScoutCommand(arguments: ["sample", "extra"]) == nil)
        #expect(ScoutCommand(arguments: ["status", "extra"]) == nil)
    }
}
