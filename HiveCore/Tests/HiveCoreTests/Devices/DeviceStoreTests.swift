import CryptoKit
import Foundation
@testable import HiveCore
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
        let device = try store.add(name: "Studio Mac", publicKey: key, at: now)

        // Act
        let found = try store.device(id: device.id)

        // Assert
        #expect(found == device)
    }

    @Test("A key that's already paired can't be paired again")
    func refusesSameKeyTwice() throws {
        // Arrange
        _ = try store.add(name: "Studio Mac", publicKey: key, at: now)

        // Act, Assert
        #expect(throws: DeviceStoreError.alreadyPaired) {
            try store.add(name: "Another", publicKey: key, at: now)
        }
    }

    @Test("Removing a device removes only that device")
    func removesOnlyThatDevice() throws {
        // Arrange
        let removed = try store.add(name: "Old Mac", publicKey: key, at: now)
        let kept = try store.add(name: "Studio Mac", publicKey: P256.Signing.PrivateKey().publicKey.x963Representation, at: now)

        // Act
        try store.remove(id: removed.id)

        // Assert
        #expect(try store.device(id: removed.id) == nil)
        #expect(try store.device(id: kept.id) == kept)
    }
}
