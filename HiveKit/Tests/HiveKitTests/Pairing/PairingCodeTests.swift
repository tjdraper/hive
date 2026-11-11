import CryptoKit
import Foundation
import HiveKit
import Testing

struct PairingCodeTests {
    private let code = PairingCode(
        hiveID: UUID(),
        pin: PublicKeyPin(publicKey: P256.Signing.PrivateKey().publicKey),
        token: Data((0 ..< PairingCode.tokenLength).map(UInt8.init)),
        addresses: [
            HiveAddress(host: "studio.tail0000.ts.net", port: 4483),
            HiveAddress(host: "fd7a:115c:a1e0::1", port: 4483),
            HiveAddress(host: "hive.example.com", port: 443),
        ]
    )

    @Test("A code reads back as written, with its addresses in order")
    func roundTrip() {
        // Act
        let read = PairingCode(text: code.text)

        // Assert
        #expect(read == code)
    }

    @Test("A code reads back with spaces and line breaks in it, such as from a message that wrapped it")
    func ignoresWhitespace() {
        // Arrange
        let text = code.text
        let middle = text.index(text.startIndex, offsetBy: text.count / 2)
        let wrapped = "  " + text[..<middle] + "\n " + text[middle...] + "\n"

        // Act
        let read = PairingCode(text: wrapped)

        // Assert
        #expect(read == code)
    }

    @Test("A code is short enough to copy and scan")
    func length() {
        // Act
        let text = code.text
        let isASCII = text.allSatisfy(\.isASCII)

        // Assert
        #expect(text.count < 250)
        #expect(isASCII)
    }

    @Test(
        "Anything that isn't a whole code is refused",
        arguments: [
            "",
            "hive1:",
            "hive2:AAAA",
            "https://hive.example.com",
            "hive1:not base64!",
        ]
    )
    func refusesOtherText(text: String) {
        // Act, Assert
        #expect(PairingCode(text: text) == nil)
    }

    @Test("A code cut short or with more after it is refused")
    func refusesDamagedCode() {
        // Arrange
        let text = code.text

        // Act, Assert
        #expect(PairingCode(text: String(text.dropLast(4))) == nil)
        #expect(PairingCode(text: text + "AAAA") == nil)
    }

    @Test("A code without an address is refused, since it gives the device nowhere to go")
    func refusesNoAddresses() {
        // Arrange
        let empty = PairingCode(hiveID: code.hiveID, pin: code.pin, token: code.token, addresses: [])

        // Act, Assert
        #expect(PairingCode(text: empty.text) == nil)
    }
}
