import Foundation
import HiveKit
import Testing

struct BuildExpiryResolverTests {
    private static let day: TimeInterval = 24 * 60 * 60

    private static func sampleProfile() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "SampleAdHoc", withExtension: "mobileprovision"))
        return try Data(contentsOf: url)
    }

    /// A profile's property list between bytes that stand in for its signature.
    private static func profile(expiring: String, allowsDebugging: Bool) -> Data {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>Entitlements</key><dict><key>get-task-allow</key><\(allowsDebugging)/></dict>
        <key>ExpirationDate</key><date>\(expiring)</date>
        </dict></plist>
        """
        return Data([0x30, 0x82, 0x06, 0xB4]) + Data(plist.utf8) + Data([0xA0, 0x82, 0x01, 0x00, 0x3C])
    }

    @Test("Reads ExpirationDate from a signed provisioning profile")
    func readsSampleProfile() throws {
        // Arrange
        let data = try Self.sampleProfile()

        // Act
        let profile = try #require(ProvisioningProfile(data: data))

        // Assert
        #expect(profile.expirationDate == Date(timeIntervalSince1970: 1_825_070_400))
        #expect(!profile.allowsDebugging)
    }

    @Test("Refuses data with no property list in it")
    func refusesOtherData() {
        // Arrange
        let data = Data("not a provisioning profile".utf8)

        // Act
        let profile = ProvisioningProfile(data: data)

        // Assert
        #expect(profile == nil)
    }

    @Test("A build with an ad hoc profile expires with the profile")
    func adHocExpiresWithProfile() throws {
        // Arrange
        let data = try Self.sampleProfile()

        // Act
        let build = BuildExpiryResolver.mobileBuild(
            platform: .iPhone, version: "2026.3", build: "12", provisioningProfile: data, buildDate: ""
        )

        // Assert
        #expect(build.distribution == .adHoc)
        #expect(build.expiresAt == Date(timeIntervalSince1970: 1_825_070_400))
    }

    @Test("A profile that allows debugging is a development build")
    func developmentProfile() {
        // Arrange
        let data = Self.profile(expiring: "2026-11-21T09:30:00Z", allowsDebugging: true)

        // Act
        let build = BuildExpiryResolver.mobileBuild(
            platform: .iPad, version: "2026.3", build: "12", provisioningProfile: data, buildDate: nil
        )

        // Assert
        #expect(build.distribution == .development)
        #expect(build.expiresAt == Date(timeIntervalSince1970: 1_795_253_400))
    }

    @Test("Without a profile it's TestFlight, expiring 90 days after the build date")
    func testFlightExpiresAfterNinetyDays() {
        // Arrange
        let buildDate = "2026-11-14T17:00:00Z"

        // Act
        let build = BuildExpiryResolver.mobileBuild(
            platform: .iPhone, version: "2026.3", build: "12", provisioningProfile: nil, buildDate: buildDate
        )

        // Assert
        #expect(build.distribution == .testFlight)
        #expect(build.expiresAt == Date(timeIntervalSince1970: 1_794_675_600).addingTimeInterval(90 * Self.day))
    }

    @Test("A TestFlight build without a build date has no expiry", arguments: [nil, "", "yesterday"])
    func testFlightWithoutBuildDate(buildDate: String?) {
        // Arrange
        let version = "2026.3"

        // Act
        let build = BuildExpiryResolver.mobileBuild(
            platform: .iPhone, version: version, build: "12", provisioningProfile: nil, buildDate: buildDate
        )

        // Assert
        #expect(build.distribution == .testFlight)
        #expect(build.expiresAt == nil)
    }
}
