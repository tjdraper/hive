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

    @Test("Unknown commands and extra arguments are refused")
    func unknown() {
        #expect(ScoutCommand(arguments: []) == nil)
        #expect(ScoutCommand(arguments: ["sample", "extra"]) == nil)
        #expect(ScoutCommand(arguments: ["run"]) == nil)
    }
}
