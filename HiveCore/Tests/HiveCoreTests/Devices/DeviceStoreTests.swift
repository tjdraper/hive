import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct DeviceStoreTests {
    private let store: DeviceStore
    private let key = P256.Signing.PrivateKey().publicKey.x963Representation
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        store = DeviceStore(database: try HiveDatabase.inMemory())
    }

    @Test("A paired device can be found by its ID")
    func findsPairedDevice() throws {
        // Arrange
        let device = try store.add(name: "Studio Mac", publicKey: key, at: now, auditedAs: .pairedOnHiveMac)

        // Act
        let found = try store.device(id: device.id)

        // Assert
        #expect(found == device)
    }

    @Test("A key that's already paired can't be paired again")
    func refusesSameKeyTwice() throws {
        // Arrange
        _ = try store.add(name: "Studio Mac", publicKey: key, at: now, auditedAs: .pairedOnHiveMac)

        // Act, Assert
        #expect(throws: DeviceStoreError.alreadyPaired) {
            try store.add(name: "Another", publicKey: key, at: now, auditedAs: .pairedOnHiveMac)
        }
    }

    @Test("Removing a device removes only that device")
    func removesOnlyThatDevice() throws {
        // Arrange
        let removed = try store.add(name: "Old Mac", publicKey: key, at: now, auditedAs: .pairedOnHiveMac)
        let otherKey = P256.Signing.PrivateKey().publicKey.x963Representation
        let kept = try store.add(name: "Studio Mac", publicKey: otherKey, at: now, auditedAs: .pairedOnHiveMac)

        // Act
        _ = try store.remove(id: removed.id, by: kept.id, at: now)

        // Assert
        #expect(try store.device(id: removed.id) == nil)
        #expect(try store.device(id: kept.id) == kept)
    }
}
