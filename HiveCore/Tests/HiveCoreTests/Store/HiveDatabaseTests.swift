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

    @Test("A store from before servers keeps its Hive ID, devices, settings and audit log, and starts with no servers")
    func migratesFromSettingsSchema() throws {
        // Arrange
        let writer = try HiveDatabase.inMemory(migratedUpTo: "Add the Hive's settings and the audit log")
        let hiveID = try writer.read { try UUID.fetchOne($0, sql: "SELECT id FROM hive") }
        let deviceID = UUID()
        try writer.write { database in
            try database.execute(
                sql: "INSERT INTO device (id, name, publicKey, pairedAt) VALUES (?, ?, ?, ?)",
                arguments: [deviceID, "Studio Mac", P256.Signing.PrivateKey().publicKey.x963Representation, Date()]
            )
            try database.execute(sql: "UPDATE hive SET name = 'Studio Hive', port = 5000")
            try AuditLog.record(.pairedOnHiveMac, by: deviceID, at: Date(), in: database)
        }

        // Act
        let database = try HiveDatabase.migrate(writer, defaultHiveName: "Ignored")

        // Assert
        #expect(try database.hiveID() == hiveID)
        #expect(try DeviceStore(database: database).device(id: deviceID)?.name == "Studio Mac")
        let settings = try HiveSettingsStore(database: database, defaultPort: 4483).settings()
        #expect(settings == HiveSettings(name: "Studio Hive", networkAccess: .thisMacOnly, port: 5000))
        #expect(try AuditLog(database: database).page(before: nil, limit: 10).entries.map(\.event) == [.pairedOnHiveMac])
        #expect(try ServerStore(database: database).all().isEmpty)
        #expect(try BackupJobStore(database: database).all().isEmpty)
    }

    @Test("A store from before SSH keys keeps its servers, which have no key until one is made")
    func migratesFromServersSchema() throws {
        // Arrange
        let writer = try HiveDatabase.inMemory(migratedUpTo: "Add servers and backup jobs")
        let serverID = UUID()
        try writer.write { database in
            try database.execute(
                sql: "INSERT INTO server (id, name, host, port, user, createdAt) VALUES (?, 'Web', 'web.example.com', 22, 'root', ?)",
                arguments: [serverID, Date()]
            )
        }

        // Act
        let database = try HiveDatabase.migrate(writer, defaultHiveName: "Ignored")

        // Assert
        let server = try #require(try ServerStore(database: database).server(id: serverID))
        #expect(server.name == "Web")
        #expect(server.sshKeyFingerprint == nil)
        #expect(server.confirmedHostKey == nil)
    }

    @Test("A store from before snapshots keeps its servers and jobs, with no drive chosen and no snapshots")
    func migratesFromSSHKeysSchema() throws {
        // Arrange
        let writer = try HiveDatabase.inMemory(migratedUpTo: "Add Hive's SSH key for each server")
        let serverID = UUID()
        let jobID = UUID()
        try writer.write { database in
            try database.execute(
                sql: "INSERT INTO server (id, name, host, port, user, createdAt) VALUES (?, 'Web', 'web.example.com', 22, 'root', ?)",
                arguments: [serverID, Date()]
            )
            try database.execute(
                sql: """
                INSERT INTO backupJob (id, serverID, name, dailySnapshots, monthlySnapshots, createdAt)
                VALUES (?, ?, 'Site', 14, 12, ?)
                """,
                arguments: [jobID, serverID, Date()]
            )
        }

        // Act
        let database = try HiveDatabase.migrate(writer, defaultHiveName: "Ignored")

        // Assert
        #expect(try ServerStore(database: database).server(id: serverID)?.name == "Web")
        #expect(try BackupJobStore(database: database).job(id: jobID)?.name == "Site")
        #expect(try BackupDriveStore(database: database).chosen() == nil)
        #expect(try SnapshotCatalog(database: database).snapshots(ofJob: jobID, onDrive: UUID(), in: .complete).isEmpty)
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
