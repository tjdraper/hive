import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct SettingsRoutesTests {
    private let fixture: APIFixture

    init() throws {
        fixture = try APIFixture()
    }

    private func put(_ settings: HiveSettings) async throws -> (status: HTTPResponse.Status, body: TestResponse) {
        let token = try fixture.token()
        return try await fixture.application.test(.router) { client in
            try await client.execute(
                uri: HiveEndpoint.settings,
                method: .put,
                headers: fixture.headers(token: token),
                body: ByteBuffer(bytes: try JSONEncoder().encode(settings))
            ) { ($0.status, $0) }
        }
    }

    private var current: HiveSettings {
        get throws { try fixture.settings.settings() }
    }

    @Test("The settings start with the Mac's name, this Mac only, and the default port")
    func readsSettings() async throws {
        // Arrange
        let token = try fixture.token()

        // Act
        let state = try await fixture.application.test(.router) { client in
            try await client.execute(uri: HiveEndpoint.settings, method: .get, headers: fixture.headers(token: token)) { response in
                #expect(response.status == .ok)
                return try response.decoded(as: HiveSettingsState.self)
            }
        }

        // Assert
        #expect(state.settings == HiveSettings(name: "Test Hive", networkAccess: .thisMacOnly, port: APIFixture.defaultPort))
        #expect(state.listeningOn == ["127.0.0.1"])
    }

    @Test("Renaming the Hive saves the new name and records who did it")
    func renames() async throws {
        // Arrange
        var settings = try current
        settings.name = "  Studio Hive "

        // Act
        let (status, response) = try await put(settings)

        // Assert
        #expect(status == .ok)
        #expect(try response.decoded(as: HiveSettingsState.self).settings.name == "Studio Hive")
        #expect(try current.name == "Studio Hive")
        let entry = try #require(try fixture.auditLog.page(before: nil, limit: 1).entries.first)
        #expect(entry.event == .hiveRenamed(old: "Test Hive", new: "Studio Hive"))
        #expect(entry.deviceID == fixture.signIn.device.id)
        #expect(entry.deviceName == "Test Mac")
        #expect(fixture.listeners.applied.isEmpty)
    }

    @Test("Choosing an address takes effect at once, in its canonical form, and is recorded")
    func choosesAddress() async throws {
        // Arrange
        var settings = try current
        settings.networkAccess = .address("FD7A:115C:A1E0::1")

        // Act
        let (status, _) = try await put(settings)

        // Assert
        #expect(status == .ok)
        #expect(fixture.listeners.applied == [ListenTarget(networkAccess: .address("fd7a:115c:a1e0::1"), port: APIFixture.defaultPort)])
        #expect(try current.networkAccess == .address("fd7a:115c:a1e0::1"))
        #expect(try fixture.auditEvents().first == .networkAccessChanged(old: .thisMacOnly, new: .address("fd7a:115c:a1e0::1")))
    }

    @Test("Changing several settings at once records each")
    func recordsEachChange() async throws {
        // Arrange
        let settings = HiveSettings(name: "Studio Hive", networkAccess: .allAddresses, port: 5000)

        // Act
        _ = try await put(settings)

        // Assert
        #expect(try fixture.auditEvents().prefix(3) == [
            .portChanged(old: APIFixture.defaultPort, new: 5000),
            .networkAccessChanged(old: .thisMacOnly, new: .allAddresses),
            .hiveRenamed(old: "Test Hive", new: "Studio Hive"),
        ])
        #expect(fixture.listeners.applied == [ListenTarget(networkAccess: .allAddresses, port: 5000)])
    }

    @Test("Sending the settings unchanged records nothing")
    func unchangedRecordsNothing() async throws {
        // Arrange
        let before = try fixture.auditEvents()

        // Act
        let (status, _) = try await put(try current)

        // Assert
        #expect(status == .ok)
        #expect(try fixture.auditEvents() == before)
    }

    @Test(
        "A change Hive can't make is refused with the reason, changing and recording nothing",
        arguments: [
            (HiveSettings(name: " ", networkAccess: .allAddresses, port: 4483), SettingsProblem.invalidName),
            (HiveSettings(name: "Hive\u{7}", networkAccess: .allAddresses, port: 4483), .invalidName),
            (HiveSettings(name: "Hive", networkAccess: .allAddresses, port: 80), .invalidPort),
            (HiveSettings(name: "Hive", networkAccess: .allAddresses, port: 65536), .invalidPort),
            (HiveSettings(name: "Hive", networkAccess: .address("127.0.0.1"), port: 4483), .invalidAddress),
            (HiveSettings(name: "Hive", networkAccess: .address("hive.example.com"), port: 4483), .invalidAddress),
        ]
    )
    func refusesInvalidChange(settings: HiveSettings, problem: SettingsProblem) async throws {
        // Arrange
        let before = try fixture.auditEvents()

        // Act
        let (status, response) = try await put(settings)

        // Assert
        #expect(status == .unprocessableContent)
        #expect(try response.decoded(as: SettingsRefusal.self).problem == problem)
        #expect(try current == HiveSettings(name: "Test Hive", networkAccess: .thisMacOnly, port: APIFixture.defaultPort))
        #expect(try fixture.auditEvents() == before)
        #expect(fixture.listeners.applied.isEmpty)
    }

    @Test("A port that's taken is refused, and nothing is saved or recorded")
    func refusesTakenPort() async throws {
        // Arrange
        fixture.listeners.refuseLoopback()
        let before = try fixture.auditEvents()

        // Act
        let (status, response) = try await put(HiveSettings(name: "Studio Hive", networkAccess: .thisMacOnly, port: 5000))

        // Assert
        #expect(status == .unprocessableContent)
        #expect(try response.decoded(as: SettingsRefusal.self).problem == .portUnavailable)
        #expect(try current.port == APIFixture.defaultPort)
        #expect(try current.name == "Test Hive")
        #expect(try fixture.auditEvents() == before)
    }

    @Test("A body that isn't settings is refused")
    func malformedBody() async throws {
        // Arrange
        let token = try fixture.token()

        // Act
        try await fixture.application.test(.router) { client in
            try await client.execute(
                uri: HiveEndpoint.settings,
                method: .put,
                headers: fixture.headers(token: token),
                body: ByteBuffer(string: "{\"name\": 1}")
            ) { response in
                // Assert
                #expect(response.status == .badRequest)
            }
        }
    }
}
