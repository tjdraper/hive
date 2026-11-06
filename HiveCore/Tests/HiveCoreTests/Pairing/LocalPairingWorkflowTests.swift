import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct LocalPairingWorkflowTests {
    private let hiveID = UUID()
    private let pin = PublicKeyPin(publicKey: P256.Signing.PrivateKey().publicKey)
    private let devices: DeviceStore
    private let workflow: LocalPairingWorkflow
    private let deviceKey = P256.Signing.PrivateKey().publicKey.x963Representation

    init() throws {
        devices = DeviceStore(database: try HiveDatabase.inMemory())
        workflow = LocalPairingWorkflow(hiveID: hiveID, pin: pin, port: 4483, devices: devices)
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
