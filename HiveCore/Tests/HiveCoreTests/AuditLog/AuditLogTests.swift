import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct AuditLogTests {
    private let fixture: APIFixture

    init() throws {
        fixture = try APIFixture()
    }

    private func rename(to names: [String]) throws {
        var old = try fixture.settings.settings()
        for name in names {
            var new = old
            new.name = name
            try fixture.settings.save(new, replacing: old, by: fixture.signIn.device.id, at: fixture.signIn.clock.now)
            old = new
        }
    }

    @Test("Entries come newest first, a page at a time")
    func pagesNewestFirst() throws {
        // Arrange
        try rename(to: ["One", "Two", "Three"])

        // Act
        let first = try fixture.auditLog.page(before: nil, limit: 2)
        let second = try fixture.auditLog.page(before: first.nextBefore, limit: 2)

        // Assert
        #expect(first.entries.map(\.event) == [.hiveRenamed(old: "Two", new: "Three"), .hiveRenamed(old: "One", new: "Two")])
        #expect(second.entries.map(\.event) == [.hiveRenamed(old: "Test Hive", new: "One"), .pairedOnHiveMac])
        #expect(second.nextBefore == nil)
    }

    @Test("An entry keeps the name of the device that made it after the device is revoked")
    func keepsRevokedDeviceName() throws {
        // Arrange
        let other = try fixture.signIn.devices.add(
            name: "Office iPad",
            publicKey: P256.Signing.PrivateKey().publicKey.x963Representation,
            at: fixture.signIn.clock.now,
            auditedAs: .pairedOnHiveMac
        )

        // Act
        _ = try fixture.signIn.devices.remove(id: other.id, by: fixture.signIn.device.id, at: fixture.signIn.clock.now)

        // Assert
        let entries = try fixture.auditLog.page(before: nil, limit: 10).entries
        #expect(entries.contains { $0.deviceID == other.id && $0.deviceName == "Office iPad" && $0.event == .pairedOnHiveMac })
    }

    @Test("A change can't be recorded for a device that isn't paired, so neither is saved")
    func refusesUnknownDevice() throws {
        // Arrange
        let old = try fixture.settings.settings()
        var new = old
        new.name = "Taken Over"

        // Act
        #expect(throws: AuditLogError.unknownDevice) {
            try fixture.settings.save(new, replacing: old, by: UUID(), at: fixture.signIn.clock.now)
        }

        // Assert
        #expect(try fixture.settings.settings().name == "Test Hive")
    }

    @Test("The route answers with a page, starting before the entry asked for")
    func routeAnswersPage() async throws {
        // Arrange
        try rename(to: ["One", "Two"])
        let token = try fixture.token()
        let newest = try #require(try fixture.auditLog.page(before: nil, limit: 1).entries.first)

        // Act
        let page = try await fixture.application.test(.router) { client in
            try await client.execute(
                uri: "\(HiveEndpoint.auditLog)?before=\(newest.id)&limit=1",
                method: .get,
                headers: fixture.headers(token: token)
            ) { response in
                #expect(response.status == .ok)
                return try response.decoded(as: AuditLogPage.self)
            }
        }

        // Assert
        #expect(page.entries.map(\.event) == [.hiveRenamed(old: "Test Hive", new: "One")])
        #expect(page.nextBefore != nil)
    }
}
