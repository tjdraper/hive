import Foundation
@testable import HiveKit
import Testing

struct LocalNetworkServiceTests {
    @Test("The Hive ID read back from the TXT record is the one written")
    func roundTrip() {
        // Arrange
        let hiveID = UUID()

        // Act
        let record = LocalNetworkService.txtRecord(hiveID: hiveID)

        // Assert
        #expect(LocalNetworkService.hiveID(inTXTRecord: record) == hiveID)
    }

    @Test("The Hive ID is found among other entries")
    func amongOtherEntries() {
        // Arrange
        let hiveID = UUID()
        let other = Data("txtvers=1".utf8)
        let record = Data([UInt8(other.count)]) + other + LocalNetworkService.txtRecord(hiveID: hiveID)

        // Act
        let found = LocalNetworkService.hiveID(inTXTRecord: record)

        // Assert
        #expect(found == hiveID)
    }

    @Test("A record that's cut short, empty or names no Hive gives no ID", arguments: [
        Data([40]) + Data("hive=".utf8),
        Data(),
        Data([9]) + Data("hive=nope".utf8),
    ])
    func unreadableRecord(record: Data) {
        // Act
        let found = LocalNetworkService.hiveID(inTXTRecord: record)

        // Assert
        #expect(found == nil)
    }

    @Test("A long name is cut to 63 bytes without splitting a character")
    func longName() {
        // Arrange
        let name = String(repeating: "é", count: 40)

        // Act
        let instance = LocalNetworkService.instanceName(for: name)

        // Assert
        #expect(instance.utf8.count == 62)
        #expect(instance == String(repeating: "é", count: 31))
    }
}
