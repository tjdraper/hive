import Foundation
@testable import HiveCore
import Testing

struct HiveDatabaseTests {
    @Test("The Hive ID is created with the store and stays the same when it's opened again")
    func hiveIDIsCreatedOnce() throws {
        // Arrange
        let temporary = try TemporaryDirectory()
        let first = try HiveDatabase.open(in: temporary.url).hiveID()

        // Act
        let second = try HiveDatabase.open(in: temporary.url).hiveID()

        // Assert
        #expect(first == second)
    }

    @Test("Two stores have different Hive IDs")
    func hiveIDsDiffer() throws {
        // Act
        let first = try HiveDatabase.inMemory().hiveID()
        let second = try HiveDatabase.inMemory().hiveID()

        // Assert
        #expect(first != second)
    }
}
