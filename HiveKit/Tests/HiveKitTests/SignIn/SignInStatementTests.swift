import Foundation
import HiveKit
import Testing

struct SignInStatementTests {
    private let hiveID = UUID()
    private let deviceID = UUID()
    private let challenge = Data(repeating: 7, count: 57)

    @Test("The statement is the same every time for the same Hive, device and challenge")
    func statementIsStable() {
        // Act
        let first = SignInStatement.bytes(hiveID: hiveID, deviceID: deviceID, challenge: challenge)
        let second = SignInStatement.bytes(hiveID: hiveID, deviceID: deviceID, challenge: challenge)

        // Assert
        #expect(first == second)
    }

    @Test("Another Hive, device or challenge gives another statement")
    func statementNamesEachPart() {
        // Arrange
        let statement = SignInStatement.bytes(hiveID: hiveID, deviceID: deviceID, challenge: challenge)

        // Act
        let others = [
            SignInStatement.bytes(hiveID: UUID(), deviceID: deviceID, challenge: challenge),
            SignInStatement.bytes(hiveID: hiveID, deviceID: UUID(), challenge: challenge),
            SignInStatement.bytes(hiveID: hiveID, deviceID: deviceID, challenge: Data(repeating: 8, count: 57)),
            SignInStatement.bytes(hiveID: deviceID, deviceID: hiveID, challenge: challenge),
        ]

        // Assert
        #expect(others.allSatisfy { $0 != statement })
    }
}
