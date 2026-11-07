import HiveKit
import Testing

struct ServerSSHKeyTests {
    private let key = ServerSSHKey(
        publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOT2Foa0mQ4Vw3Y5Z5moKT7BMkzbCI+js4Nj07VccOAW",
        fingerprint: "SHA256:example",
        comment: "Hive Studio",
        macAddresses: []
    )

    @Test("The authorized_keys line is restricted, and limited to the given addresses")
    func authorizedKeysLine() {
        // Act
        let open = key.authorizedKeysLine()
        let limited = key.authorizedKeysLine(acceptingFrom: ["100.64.0.7", "fd7a:115c:a1e0::7"])

        // Assert
        #expect(open == "restrict \(key.publicKey) Hive Studio")
        #expect(limited == "restrict,from=\"100.64.0.7,fd7a:115c:a1e0::7\" \(key.publicKey) Hive Studio")
    }
}
