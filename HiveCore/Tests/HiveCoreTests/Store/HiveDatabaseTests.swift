import CryptoKit
import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Testing

struct HiveDatabaseTests {
    @Test("The Hive ID is created with the store and stays the same when it's opened again")
    func hiveIDIsCreatedOnce() throws {
        // Arrange
        let temporary = try TemporaryDirectory()
        let first = try HiveDatabase.open(in: temporary.url, defaultHiveName: "Studio Mac").hiveID()

        // Act
        let second = try HiveDatabase.open(in: temporary.url, defaultHiveName: "Studio Mac").hiveID()

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

    @Test("A store from before settings keeps its Hive ID and devices, and is named for the Mac")
    func migratesFromFirstSchema() throws {
        // Arrange
        let writer = try HiveDatabase.inMemory(migratedUpTo: "Create the Hive and its devices")
        let hiveID = try writer.read { try UUID.fetchOne($0, sql: "SELECT id FROM hive") }
        let deviceID = UUID()
        try writer.write { database in
            try database.execute(
                sql: "INSERT INTO device (id, name, publicKey, pairedAt) VALUES (?, ?, ?, ?)",
                arguments: [deviceID, "Studio Mac", P256.Signing.PrivateKey().publicKey.x963Representation, Date()]
            )
        }

        // Act
        let database = try HiveDatabase.migrate(writer, defaultHiveName: "Studio Mac mini")

        // Assert
        #expect(try database.hiveID() == hiveID)
        #expect(try DeviceStore(database: database).device(id: deviceID)?.name == "Studio Mac")
        let settings = try HiveSettingsStore(database: database, defaultPort: 4483).settings()
        #expect(settings == HiveSettings(name: "Studio Mac mini", networkAccess: .thisMacOnly, port: 4483))
    }

    @Test("A Mac name that isn't a valid name gives a Hive named Hive")
    func invalidMacNameFallsBack() throws {
        // Arrange
        let temporary = try TemporaryDirectory()

        // Act
        let database = try HiveDatabase.open(in: temporary.url, defaultHiveName: " \n")

        // Assert
        #expect(try HiveSettingsStore(database: database, defaultPort: 4483).settings().name == "Hive")
    }
}
