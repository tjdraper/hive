import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

struct BuildExpiryWarningTests {
    private static let day: TimeInterval = 24 * 60 * 60
    private static let address = ClientAddress(key: "192.0.2.1")
    /// Hive's email names the device as it paired.
    private static let firstWarning = "Beekeeper on “Test Mac” expires on"
    private static let lastWarning = "Last warning: Beekeeper on “Test Mac” expires on"

    private let fixture: AlertFixture

    init() async throws {
        fixture = try await AlertFixture()
    }

    private func build(_ number: String = "12", expiresIn days: Double, distribution: BuildDistribution = .testFlight) -> BeekeeperBuild {
        BeekeeperBuild(
            platform: .iPhone,
            version: "2026.3",
            build: number,
            distribution: distribution,
            expiresAt: fixture.clock.now.addingTimeInterval(days * Self.day)
        )
    }

    /// Signs the fixture's device in reporting `build`. Requests through `APIFixture.send` sign in reporting
    /// none, so this comes after them.
    private func report(_ build: BeekeeperBuild?, on api: APIFixture? = nil) throws {
        let signIn = (api ?? fixture.api).signIn
        let outcome = signIn.workflow.signIn(try signIn.request(build: build), from: Self.address)
        guard outcome.token != nil else { throw APIFixtureError.couldNotSignIn }
    }

    private func warnings(on api: APIFixture? = nil) throws -> [String] {
        try (fixture.sent(on: api, startingWith: Self.firstWarning) + fixture.sent(on: api, startingWith: Self.lastWarning)).map(\.subject)
    }

    @Test("Warns 14 days before a build expires, then 3 days before, once each")
    func warnsTwice() async throws {
        // Arrange
        try report(build(expiresIn: 20))

        // Act
        await fixture.check()
        let early = try warnings()
        fixture.clock.advance(by: 6 * Self.day)
        await fixture.check()
        await fixture.check()
        let first = try warnings()
        fixture.clock.advance(by: 11 * Self.day)
        await fixture.check()
        await fixture.check()
        let last = try warnings()
        fixture.clock.advance(by: 4 * Self.day)
        await fixture.check()

        // Assert
        #expect(early.isEmpty)
        #expect(first == ["Beekeeper on “Test Mac” expires on Thursday 4 February"])
        #expect(last == [
            "Beekeeper on “Test Mac” expires on Thursday 4 February",
            "Last warning: Beekeeper on “Test Mac” expires on Thursday 4 February",
        ])
        #expect(try warnings() == last)
    }

    @Test("A build first reported with less than 3 days left gets only the last warning")
    func onlyLastWarningWhenLate() async throws {
        // Arrange
        try report(build(expiresIn: 2))

        // Act
        await fixture.check()
        fixture.clock.advance(by: Self.day)
        await fixture.check()

        // Assert
        #expect(try warnings() == ["Last warning: Beekeeper on “Test Mac” expires on Sunday 17 January"])
    }

    @Test("A new build starts the warnings over")
    func newBuildStartsOver() async throws {
        // Arrange
        try report(build("12", expiresIn: 10))
        await fixture.check()

        // Act
        try report(build("13", expiresIn: 10))
        await fixture.check()

        // Assert
        #expect(try warnings() == [
            "Beekeeper on “Test Mac” expires on Monday 25 January",
            "Beekeeper on “Test Mac” expires on Monday 25 January",
        ])
    }

    @Test("The same build reported again doesn't start the warnings over")
    func sameBuildKeepsWarnings() async throws {
        // Arrange
        try report(build(expiresIn: 10))
        await fixture.check()

        // Act
        fixture.clock.advance(by: 60)
        try report(build(expiresIn: 10 - 60 / Self.day))
        await fixture.check()

        // Assert
        #expect(try warnings().count == 1)
    }

    @Test("A build that has already expired, or never expires, isn't warned about")
    func noWarningWithoutExpiry() async throws {
        // Arrange
        let mac = BeekeeperBuild(platform: .mac, version: "2026.3", build: "12", distribution: .developerID, expiresAt: nil)
        try report(build(expiresIn: -1))
        await fixture.check()

        // Act
        try report(mac)
        await fixture.check()

        // Assert
        #expect(try warnings().isEmpty)
    }

    @Test("With build expiry warnings turned off, nothing is sent")
    func turnedOffSendsNothing() async throws {
        // Arrange
        var settings = try fixture.api.settings.settings()
        settings.sendsBuildExpiryWarnings = false
        let answer = try await fixture.api.send(.put, HiveEndpoint.settings, json: settings)
        #expect(answer.status == .ok)
        try report(build(expiresIn: 10))

        // Act
        await fixture.check()
        fixture.clock.advance(by: 8 * Self.day)
        await fixture.check()

        // Assert
        #expect(try warnings().isEmpty)
    }

    @Test("A warning sent before a restart isn't sent again after it")
    func notSentTwiceAcrossRestart() async throws {
        // Arrange
        try report(build(expiresIn: 10))
        await fixture.check()

        // Act
        let restarted = try APIFixture(signIn: fixture.api.signIn, sealer: fixture.api.sealer)
        await fixture.check(on: restarted)

        // Assert
        #expect(try warnings().count == 1)
        #expect(try warnings(on: restarted).isEmpty)
    }

    @Test("A revoked device's warning still names it")
    func revokedDeviceNamed() async throws {
        // Arrange
        try report(build(expiresIn: 10))
        await fixture.api.api.alerts.check()

        // Act
        let device = fixture.api.signIn.device
        _ = try fixture.api.signIn.devices.remove(id: device.id, by: device.id, at: fixture.clock.now)
        await fixture.api.api.alerts.mailer.sendOwed()
        await fixture.api.api.alerts.mailer.waitUntilIdle()

        // Assert
        #expect(try warnings() == ["Beekeeper on “Test Mac” expires on Monday 25 January"])
    }

    @Test("The email says which build it is, how it was installed and when it stops opening", arguments: [
        (BuildDistribution.testFlight, "is a TestFlight build, which stops opening on", "Install a newer build from TestFlight"),
        (.adHoc, "is an ad hoc build, which stops opening when its provisioning profile expires on", "Install a newer build"),
        (
            .development,
            "was installed from Xcode, and stops opening when its provisioning profile expires on",
            "Build and install it again"
        ),
    ])
    func emailExplains(distribution: BuildDistribution, explanation: String, action: String) async throws {
        // Arrange
        try report(build(expiresIn: 10, distribution: distribution))

        // Act
        await fixture.check()

        // Assert
        let email = try #require(try fixture.sent(startingWith: Self.firstWarning).first)
        #expect(email.body.contains("Beekeeper 2026.3 (12) on “Test Mac” \(explanation) Monday 25 January 2027 at 03:00 EST."))
        #expect(email.body.contains("\(action) before then."))
        #expect(email.body.contains("You'll get one more warning 3 days before it expires."))
    }
}
