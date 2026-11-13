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

    private func advertised(_ name: String) -> AdvertisedHive {
        AdvertisedHive(hiveID: fixture.api.hiveID, name: name)
    }

    private static func withOptions(_ options: [AddressOption]) -> HiveSettings {
        HiveSettings(name: "Hive", networkAccess: .allAddresses, port: 4483, addressOptions: options)
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

    @Test("Renaming the Hive saves the new name, records who did it, and advertises it under the new name")
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
        #expect(fixture.listeners.applied.map(\.advertised) == [advertised("Studio Hive")])
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
        #expect(fixture.listeners.applied == [
            ListenTarget(networkAccess: .address("fd7a:115c:a1e0::1"), port: APIFixture.defaultPort, advertised: advertised("Test Hive")),
        ])
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
        let target = ListenTarget(networkAccess: .allAddresses, port: 5000, advertised: advertised("Studio Hive"))
        #expect(fixture.listeners.applied == [target])
    }

    @Test("Turning off advertising on the local network stops it and is recorded")
    func turnsOffAdvertising() async throws {
        // Arrange
        var settings = try current
        settings.advertisesOnLocalNetwork = false

        // Act
        let (status, _) = try await put(settings)

        // Assert
        #expect(status == .ok)
        #expect(try current.advertisesOnLocalNetwork == false)
        #expect(try fixture.auditEvents().first == .localNetworkAdvertisingChanged(isOn: false))
        #expect(fixture.listeners.applied == [ListenTarget(networkAccess: .thisMacOnly, port: APIFixture.defaultPort, advertised: nil)])
    }

    @Test("Settings from a Beekeeper that predates advertising leave it on")
    func missingAdvertisingDecodesAsOn() throws {
        // Arrange
        let json = Data(#"{"name":"Hive","networkAccess":{"thisMacOnly":{}},"port":4483,"addressOptions":[]}"#.utf8)

        // Act
        let settings = try JSONDecoder().decode(HiveSettings.self, from: json)

        // Assert
        #expect(settings.advertisesOnLocalNetwork)
    }

    @Test("Address options are saved in one written form, in order, and recorded")
    func savesAddressOptions() async throws {
        // Arrange
        var settings = try current
        settings.addressOptions = [
            AddressOption(host: " Studio.tail0000.ts.net. "),
            AddressOption(host: "[FD7A:115C:A1E0::1]"),
            AddressOption(host: "hive.example.com", port: 443),
        ]
        let expected = [
            AddressOption(host: "studio.tail0000.ts.net"),
            AddressOption(host: "fd7a:115c:a1e0::1"),
            AddressOption(host: "hive.example.com", port: 443),
        ]

        // Act
        let (status, _) = try await put(settings)

        // Assert
        #expect(status == .ok)
        #expect(try current.addressOptions == expected)
        #expect(try fixture.auditEvents().first == .addressOptionsChanged(old: [], new: expected))
        #expect(fixture.listeners.applied.isEmpty)
    }

    @Test("A device's live updates hear of a new port or address options as they're saved")
    func changesReachLiveUpdates() async throws {
        // Arrange
        let changes = fixture.api.addressChanges.listen()
        var settings = try current
        settings.port = 5000
        settings.addressOptions = [AddressOption(host: "hive.example.com"), AddressOption(host: "tunnel.example.net", port: 31337)]

        // Act
        _ = try await put(settings)

        // Assert
        var iterator = changes.makeAsyncIterator()
        #expect(await iterator.next() == HiveAddresses(port: 5000, options: [
            HiveAddress(host: "hive.example.com", port: 5000),
            HiveAddress(host: "tunnel.example.net", port: 31337),
        ]))
    }

    @Test("Hive suggests where other devices could reach it, by name as well as by address, with what each is")
    func suggestsHosts() async throws {
        // Act
        let state = try await fixture.api.settings.state()

        // Assert
        #expect(state.suggestedHosts == [
            SuggestedHost(host: "studio.local", label: "This Mac's name on the local network", address: nil),
            SuggestedHost(host: "192.168.1.20", label: "Wi-Fi", address: "192.168.1.20"),
            SuggestedHost(host: "studio.tail0000.ts.net", label: "Tailscale name", address: "100.64.0.7"),
            SuggestedHost(host: "100.64.0.7", label: "Tailscale", address: "100.64.0.7"),
        ])
    }

    @Test(
        "A suggestion is only offered where Hive listens: its own address, or any for all of them",
        arguments: [
            (NetworkAccess.thisMacOnly, [String]()),
            (.address("100.64.0.7"), ["studio.tail0000.ts.net", "100.64.0.7"]),
            (.address("192.168.1.99"), []),
            (.allAddresses, ["studio.local", "192.168.1.20", "studio.tail0000.ts.net", "100.64.0.7"]),
        ]
    )
    func suggestionsFollowListening(access: NetworkAccess, expected: [String]) async throws {
        // Act
        let state = try await fixture.api.settings.state()

        // Assert
        #expect(state.suggestedHosts.filter { $0.isReachable(through: access) }.map(\.host) == expected)
    }

    @Test("Each of the Mac's addresses says what it is: Tailscale's as Tailscale, others as macOS names them, if it does")
    func labelsInterfaces() async throws {
        // Arrange
        fixture.addresses.set([
            NetworkInterfaceAddress(interface: "en0", address: "192.168.1.20"),
            NetworkInterfaceAddress(interface: "utun4", address: "100.64.0.7"),
            NetworkInterfaceAddress(interface: "utun4", address: "fd7a:115c:a1e0::7"),
            NetworkInterfaceAddress(interface: "utun2", address: "100.200.0.1"),
            NetworkInterfaceAddress(interface: "bridge100", address: "192.168.139.3"),
        ])

        // Act
        let state = try await fixture.api.settings.state()

        // Assert
        #expect(state.interfaces.map(\.displayName) == ["Wi-Fi", "Tailscale", "Tailscale", nil, nil])
        #expect(state.interfaces.map(\.hostName) == [nil, "studio.tail0000.ts.net", nil, nil, nil])
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
            (Self.withOptions([AddressOption(host: "https://hive.example.com")]), .invalidAddressOption),
            (Self.withOptions([AddressOption(host: "hive.example.com/path")]), .invalidAddressOption),
            (Self.withOptions([AddressOption(host: "-hive.example.com")]), .invalidAddressOption),
            (Self.withOptions([AddressOption(host: "300.1.1.1")]), .invalidAddressOption),
            (Self.withOptions([AddressOption(host: "127.0.0.1")]), .invalidAddressOption),
            (Self.withOptions([AddressOption(host: "fe80::1")]), .invalidAddressOption),
            (Self.withOptions([AddressOption(host: "localhost")]), .invalidAddressOption),
            (Self.withOptions([AddressOption(host: "")]), .invalidAddressOption),
            (Self.withOptions([AddressOption(host: "hive.example.com", port: 0)]), .invalidAddressOption),
            (Self.withOptions([AddressOption(host: "hive.example.com", port: 65536)]), .invalidAddressOption),
            (Self.withOptions([AddressOption(host: "hive.example.com"), AddressOption(host: "Hive.Example.com.")]), .invalidAddressOption),
            (Self.withOptions((1 ... 9).map { AddressOption(host: "hive\($0).example.com") }), .tooManyAddressOptions),
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
