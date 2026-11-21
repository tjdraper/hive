import Foundation
import ScoutProtocol
import Testing

struct EnrollmentCodeTests {
    private let code = EnrollmentCode(
        hiveID: UUID(),
        serverID: UUID(),
        pin: Data((0 ..< 32).map { UInt8($0) }),
        token: Data((100 ..< 116).map { UInt8($0) }),
        addresses: [
            EnrollmentCode.Address(host: "studio.tail0000.ts.net", port: 4483),
            EnrollmentCode.Address(host: "fd7a:115c:a1e0::1", port: 44830),
        ]
    )

    @Test("A code reads back as what was written, and its text is only `scout1:` and base64url")
    func roundTrip() {
        // Act
        let text = code.text

        // Assert
        #expect(EnrollmentCode(text: text) == code)
        #expect(text.hasPrefix("scout1:"))
        #expect(text.dropFirst(7).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
    }

    @Test("A code wrapped over lines by a terminal still reads")
    func wrapped() {
        // Arrange
        var text = code.text
        text.insert(contentsOf: "\n  ", at: text.index(text.startIndex, offsetBy: 30))

        // Act, Assert
        #expect(EnrollmentCode(text: text + "\n") == code)
    }

    @Test("Anything that isn't one whole code is refused")
    func refused() {
        let text = code.text
        #expect(EnrollmentCode(text: String(text.dropLast(4))) == nil)
        #expect(EnrollmentCode(text: text + "AAAA") == nil)
        #expect(EnrollmentCode(text: "hive1:" + text.dropFirst(7)) == nil)
        #expect(EnrollmentCode(text: text.replacingOccurrences(of: "scout1:", with: "scout1:$(")) == nil)
        #expect(EnrollmentCode(text: "") == nil)
        let noAddresses = EnrollmentCode(hiveID: code.hiveID, serverID: code.serverID, pin: code.pin, token: code.token, addresses: [])
        #expect(EnrollmentCode(text: noAddresses.text) == nil)
    }
}
