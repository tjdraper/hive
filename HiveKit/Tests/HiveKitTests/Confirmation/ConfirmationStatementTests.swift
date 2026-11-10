import Foundation
import HiveKit
import Testing

struct ConfirmationStatementTests {
    private let hiveID = UUID()
    private let deviceID = UUID()
    private let nonce = Data(repeating: 7, count: 57)
    private let body = Data("{\"quotaBytes\":1}".utf8)

    private var request: ConfirmationStatement.Request {
        ConfirmationStatement.Request(method: "PUT", path: "/servers/1", body: body)
    }

    private func statement(
        nonce: Data? = nil,
        method: String = "PUT",
        path: String = "/servers/1",
        body: Data? = nil
    ) -> Data {
        ConfirmationStatement.bytes(
            hiveID: hiveID,
            deviceID: deviceID,
            nonce: nonce ?? self.nonce,
            request: ConfirmationStatement.Request(method: method, path: path, body: body ?? self.body)
        )
    }

    @Test("Another Hive, device, nonce, method, path or body gives another statement")
    func statementNamesEachPart() {
        // Arrange
        let original = statement()

        // Act
        let others = [
            ConfirmationStatement.bytes(hiveID: UUID(), deviceID: deviceID, nonce: nonce, request: request),
            ConfirmationStatement.bytes(hiveID: hiveID, deviceID: UUID(), nonce: nonce, request: request),
            statement(nonce: Data(repeating: 8, count: 57)),
            statement(method: "POST"),
            statement(path: "/servers/2"),
            statement(body: Data("{\"quotaBytes\":2}".utf8)),
            // Moving a byte from one part to the next doesn't give the same bytes.
            statement(method: "PUT/", path: "servers/1"),
        ]

        // Assert
        #expect(statement() == original)
        #expect(others.allSatisfy { $0 != original })
    }

    @Test("A proof survives its header, and a header that isn't one is refused")
    func headerRoundTrip() {
        // Arrange
        let proof = ConfirmationProof(nonce: nonce, signature: Data(repeating: 9, count: 64))

        // Act / Assert
        #expect(ConfirmationProof(headerValue: proof.headerValue) == proof)
        #expect(ConfirmationProof(headerValue: "not a proof") == nil)
        #expect(ConfirmationProof(headerValue: "a.b.c") == nil)
    }
}
