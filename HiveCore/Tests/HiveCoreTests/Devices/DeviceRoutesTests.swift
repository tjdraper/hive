import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct DeviceRoutesTests {
    private let fixture: APIFixture
    private let otherKey = P256.Signing.PrivateKey()
    private let other: PairedDevice

    init() throws {
        fixture = try APIFixture()
        other = try fixture.signIn.devices.add(
            name: "Office iPad",
            publicKey: otherKey.publicKey.x963Representation,
            at: fixture.signIn.clock.now.addingTimeInterval(60),
            auditedAs: .pairedOnHiveMac
        )
    }

    private func status(_ method: HTTPRequest.Method, _ path: String, token: String) async throws -> HTTPResponse.Status {
        try await fixture.application.test(.router) { client in
            try await client.execute(uri: path, method: method, headers: fixture.headers(token: token)) { $0.status }
        }
    }

    @Test("The device list holds every paired device, oldest first, with when each was last seen")
    func listsDevices() async throws {
        // Arrange
        let token = try fixture.token()

        // Act
        let devices = try await fixture.application.test(.router) { client in
            try await client.execute(uri: HiveEndpoint.devices, method: .get, headers: fixture.headers(token: token)) { response in
                #expect(response.status == .ok)
                return try response.decoded(as: [DeviceSummary].self)
            }
        }

        // Assert
        #expect(devices.map(\.name) == ["Test Mac", "Office iPad"])
        #expect(devices[0].lastSeenAt == fixture.signIn.clock.now)
        #expect(devices[1].lastSeenAt == nil)
    }

    @Test("The device list shows the build each device reported when it last signed in")
    func listsBuilds() async throws {
        // Arrange
        let build = BeekeeperBuild(
            platform: .iPad,
            version: "2026.3",
            build: "12",
            distribution: .testFlight,
            expiresAt: fixture.signIn.clock.now.addingTimeInterval(90 * 24 * 60 * 60)
        )
        let request = try fixture.signIn.request(key: otherKey, deviceID: other.id, build: build)
        _ = fixture.signIn.workflow.signIn(request, from: ClientAddress(key: "192.0.2.1"))
        let token = try fixture.token()

        // Act
        let devices = try await fixture.application.test(.router) { client in
            try await client.execute(uri: HiveEndpoint.devices, method: .get, headers: fixture.headers(token: token)) { response in
                try response.decoded(as: [DeviceSummary].self)
            }
        }

        // Assert
        #expect(devices.map(\.build) == [nil, build])
    }

    @Test("Revoking a device ends its session at once and its key can't sign in again")
    func revokesAnotherDevice() async throws {
        // Arrange
        let token = try fixture.token()
        let otherToken = try fixture.token(for: other, key: otherKey)

        // Act
        let status = try await status(.delete, HiveEndpoint.device(other.id), token: token)

        // Assert
        #expect(status == .noContent)
        #expect(try await self.status(.get, HiveEndpoint.devices, token: otherToken) == .unauthorized)
        let signIn = fixture.signIn.workflow.signIn(
            try fixture.signIn.request(key: otherKey, deviceID: other.id),
            from: ClientAddress(key: "other")
        )
        #expect(signIn == .refused(.unknownDevice))
        #expect(try await self.status(.get, HiveEndpoint.devices, token: token) == .ok)
    }

    @Test("Revoking is recorded with the revoked device's name, by the device that did it")
    func revokingIsAudited() async throws {
        // Arrange
        let token = try fixture.token()

        // Act
        _ = try await status(.delete, HiveEndpoint.device(other.id), token: token)

        // Assert
        let entry = try #require(try fixture.auditLog.page(before: nil, limit: 1).entries.first)
        #expect(entry.event == .deviceRevoked(deviceID: other.id, deviceName: "Office iPad"))
        #expect(entry.deviceID == fixture.signIn.device.id)
    }

    @Test("A device can revoke itself, which ends its own session")
    func revokesItself() async throws {
        // Arrange
        let token = try fixture.token()

        // Act
        let status = try await status(.delete, HiveEndpoint.device(fixture.signIn.device.id), token: token)

        // Assert
        #expect(status == .noContent)
        #expect(try await self.status(.get, HiveEndpoint.devices, token: token) == .unauthorized)
        let entry = try #require(try fixture.auditLog.page(before: nil, limit: 1).entries.first)
        #expect(entry.deviceName == "Test Mac")
    }

    @Test("Revoking a device that isn't paired answers 404 and records nothing", arguments: [UUID().uuidString, "not-a-uuid"])
    func unknownDevice(id: String) async throws {
        // Arrange
        let token = try fixture.token()
        let before = try fixture.auditEvents()

        // Act
        let status = try await status(.delete, "\(HiveEndpoint.devices)/\(id)", token: token)

        // Assert
        #expect(status == .notFound)
        #expect(try fixture.auditEvents() == before)
    }
}
