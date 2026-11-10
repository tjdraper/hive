import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct LocalPairingWorkflowTests {
    private let hiveID = UUID()
    private let pin = PublicKeyPin(publicKey: P256.Signing.PrivateKey().publicKey)
    private let database: HiveDatabase
    private let devices: DeviceStore
    private let workflow: LocalPairingWorkflow
    private let deviceKey = P256.Signing.PrivateKey().publicKey.x963Representation
    private let restart = HiveRestart(delay: .seconds(60))

    init() throws {
        database = try HiveDatabase.inMemory()
        devices = DeviceStore(database: database)
        workflow = LocalPairingWorkflow(
            hiveID: hiveID,
            pin: pin,
            settings: HiveSettingsStore(database: database, defaultPort: 4483),
            devices: devices,
            isRestarting: { [restart] in restart.isRequested }
        )
    }

    @Test("While Hive restarts for a new identity, nothing pairs with the old one")
    func refusesWhileRestarting() throws {
        // Arrange
        restart.request()

        // Act
        let result = workflow.pair(LocalPairingRequest(devicePublicKey: deviceKey, deviceName: "Studio Mac"))

        // Assert
        #expect(result == .refused(.hiveUnavailable))
        #expect(try devices.all().isEmpty)
    }

    @Test("Pairing records the device and answers with the Hive ID, its key's pin, the port and the device's ID")
    func pairsDevice() throws {
        // Act
        let result = workflow.pair(LocalPairingRequest(devicePublicKey: deviceKey, deviceName: "  Studio Mac\n"))

        // Assert
        guard case .paired(let pairing) = result else {
            Issue.record("Expected to pair, got \(result)")
            return
        }
        #expect(pairing.hiveID == hiveID)
        #expect(pairing.pin == pin)
        #expect(pairing.port == 4483)
        let device = try #require(try devices.device(id: pairing.deviceID))
        #expect(device.name == "Studio Mac")
        #expect(device.publicKey == deviceKey)
    }

    @Test("Pairing is recorded in the audit log as made by the new device")
    func pairingIsAudited() throws {
        // Act
        let result = workflow.pair(LocalPairingRequest(devicePublicKey: deviceKey, deviceName: "Studio Mac"))

        // Assert
        guard case .paired(let pairing) = result else {
            Issue.record("Expected to pair, got \(result)")
            return
        }
        let entries = try AuditLog(database: database).page(before: nil, limit: 10).entries
        #expect(entries.map(\.event) == [.pairedOnHiveMac])
        #expect(entries.first?.deviceID == pairing.deviceID)
        #expect(entries.first?.deviceName == "Studio Mac")
    }

    @Test("Pairing answers with the port Hive listens on now, not the one it started with")
    func pairingGivesCurrentPort() throws {
        // Arrange
        let settings = HiveSettingsStore(database: database, defaultPort: 4483)
        let otherKey = P256.Signing.PrivateKey().publicKey.x963Representation
        let device = try devices.add(name: "Other Mac", publicKey: otherKey, at: .now, auditedAs: .pairedOnHiveMac)
        var changed = try settings.settings()
        changed.port = 5000
        try settings.save(changed, replacing: try settings.settings(), by: device.id, at: .now)

        // Act
        let result = workflow.pair(LocalPairingRequest(devicePublicKey: deviceKey, deviceName: "Studio Mac"))

        // Assert
        guard case .paired(let pairing) = result else {
            Issue.record("Expected to pair, got \(result)")
            return
        }
        #expect(pairing.port == 5000)
    }

    @Test(
        "A key that isn't a P-256 public key is refused",
        arguments: [Data(), Data(repeating: 4, count: 65), Data(repeating: 1, count: 33)]
    )
    func invalidKeyIsRefused(key: Data) {
        // Act
        let result = workflow.pair(LocalPairingRequest(devicePublicKey: key, deviceName: "Studio Mac"))

        // Assert
        #expect(result == .refused(.invalidKey))
    }

    @Test(
        "A name that's empty, too long, or holds control characters is refused",
        arguments: ["", "   ", String(repeating: "a", count: 101), "Studio\u{0}Mac", "Studio\u{1B}[31mMac"]
    )
    func invalidNameIsRefused(name: String) {
        // Act
        let result = workflow.pair(LocalPairingRequest(devicePublicKey: deviceKey, deviceName: name))

        // Assert
        #expect(result == .refused(.invalidName))
    }

    @Test("The same key can't be paired twice")
    func sameKeyIsRefused() {
        // Arrange
        _ = workflow.pair(LocalPairingRequest(devicePublicKey: deviceKey, deviceName: "Studio Mac"))

        // Act
        let result = workflow.pair(LocalPairingRequest(devicePublicKey: deviceKey, deviceName: "Studio Mac"))

        // Assert
        #expect(result == .refused(.alreadyPaired))
    }
}
