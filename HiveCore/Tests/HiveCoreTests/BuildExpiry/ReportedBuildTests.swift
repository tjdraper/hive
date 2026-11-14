import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct ReportedBuildTests {
    private static let day: TimeInterval = 24 * 60 * 60

    private let fixture: SignInFixture
    private let address = ClientAddress(key: "192.0.2.1")

    init() throws {
        fixture = try SignInFixture()
    }

    private func build(_ number: String = "12", version: String = "2026.3", expiresIn days: Double = 60) -> BeekeeperBuild {
        BeekeeperBuild(
            platform: .iPhone,
            version: version,
            build: number,
            distribution: .testFlight,
            expiresAt: fixture.clock.now.addingTimeInterval(days * Self.day)
        )
    }

    private func signIn(reporting build: BeekeeperBuild?) throws -> SignInOutcome {
        fixture.workflow.signIn(try fixture.request(build: build), from: address)
    }

    private func stored() throws -> PairedDevice {
        try #require(try fixture.devices.device(id: fixture.device.id))
    }

    @Test("Signing in stores the build the device reports")
    func storesBuild() throws {
        // Arrange
        let build = build()

        // Act
        let outcome = try signIn(reporting: build)

        // Assert
        #expect(outcome.token != nil)
        #expect(try stored().build == build)
    }

    @Test("A build with a version or number Hive won't store is left out, and the sign-in goes ahead", arguments: [
        ("", "12"),
        ("2026.3", ""),
        ("2026.3\n", "12"),
        ("2026.3", "<b>12</b>"),
        ("2026.3", String(repeating: "1", count: 33)),
    ])
    func leavesOutUnreadableBuild(version: String, number: String) throws {
        // Arrange
        _ = try signIn(reporting: build())

        // Act
        let outcome = try signIn(reporting: build(number, version: version))

        // Assert
        #expect(outcome.token != nil)
        #expect(try stored().build == nil)
    }

    @Test("A sign-in that reports no build clears the one before, which no longer says what the device runs")
    func noBuildClearsOld() throws {
        // Arrange
        _ = try signIn(reporting: build())

        // Act
        _ = try signIn(reporting: nil)

        // Assert
        #expect(try stored().build == nil)
    }

    @Test("A refused sign-in stores nothing")
    func refusedStoresNothing() throws {
        // Arrange
        let request = try fixture.request(deviceID: fixture.device.id, build: build())
        let forged = SignInRequest(
            deviceID: request.deviceID,
            challenge: request.challenge,
            signature: Data(repeating: 0, count: 64),
            apiVersions: request.apiVersions,
            build: request.build
        )

        // Act
        let outcome = fixture.workflow.signIn(forged, from: address)

        // Assert
        #expect(outcome == .refused(.badSignature))
        #expect(try stored().build == nil)
    }

    @Test("A sign-in whose build Hive can't read, such as from a platform added later, still signs in")
    func unreadableBuildStillSignsIn() throws {
        // Arrange
        let request = try fixture.request(build: build())
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        var reported = try #require(json["build"] as? [String: Any])
        reported["platform"] = "vision"
        json["build"] = reported
        let data = try JSONSerialization.data(withJSONObject: json)

        // Act
        let decoded = try JSONDecoder().decode(SignInRequest.self, from: data)
        let outcome = fixture.workflow.signIn(decoded, from: address)

        // Assert
        #expect(decoded.build == nil)
        #expect(outcome.token != nil)
    }
}
