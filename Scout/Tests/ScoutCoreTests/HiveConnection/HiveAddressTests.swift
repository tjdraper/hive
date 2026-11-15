import ScoutCore
import Testing

struct HiveAddressTests {
    @Test("A host and port are read, with an IPv6 address in brackets")
    func parsing() {
        #expect(HiveAddress(parsing: "100.64.0.1:4483") == HiveAddress(host: "100.64.0.1", port: 4483))
        #expect(HiveAddress(parsing: "hive.example.ts.net:4484") == HiveAddress(host: "hive.example.ts.net", port: 4484))
        #expect(HiveAddress(parsing: "[fd7a:115c:a1e0::1]:4483") == HiveAddress(host: "fd7a:115c:a1e0::1", port: 4483))
    }

    @Test("Anything without a usable host and port is refused")
    func refused() {
        #expect(HiveAddress(parsing: "100.64.0.1") == nil)
        #expect(HiveAddress(parsing: "fd7a:115c:a1e0::1:4483") == nil)
        #expect(HiveAddress(parsing: ":4483") == nil)
        #expect(HiveAddress(parsing: "[]:4483") == nil)
        #expect(HiveAddress(parsing: "host:0") == nil)
        #expect(HiveAddress(parsing: "host:65536") == nil)
        #expect(HiveAddress(parsing: "host:port") == nil)
    }
}
