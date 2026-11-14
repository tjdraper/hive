import Foundation

/// Works out how an iPhone or iPad build was distributed and when it stops opening, from what's in
/// its bundle (§16).
public enum BuildExpiryResolver {
    /// TestFlight counts from upload, which comes after the build date, so this warns a little early.
    public static let testFlightLifetime: TimeInterval = 90 * 24 * 60 * 60

    /// - Parameters:
    ///   - provisioningProfile: `embedded.mobileprovision`, which TestFlight and App Store installs
    ///     don't have.
    ///   - buildDate: `BeekeeperBuildDate` from `Info.plist`, which the release script stamps on
    ///     TestFlight builds, in ISO 8601.
    public static func mobileBuild(
        platform: BeekeeperPlatform,
        version: String,
        build: String,
        provisioningProfile: Data?,
        buildDate: String?
    ) -> BeekeeperBuild {
        let distribution: BuildDistribution
        let expiresAt: Date?
        if let provisioningProfile {
            let profile = ProvisioningProfile(data: provisioningProfile)
            distribution = profile?.allowsDebugging == true ? .development : .adHoc
            expiresAt = profile?.expirationDate
        } else {
            distribution = .testFlight
            expiresAt = buildDate
                .flatMap { try? Date.ISO8601FormatStyle().parse($0) }
                .map { $0.addingTimeInterval(testFlightLifetime) }
        }
        return BeekeeperBuild(platform: platform, version: version, build: build, distribution: distribution, expiresAt: expiresAt)
    }
}

/// What Beekeeper needs from a provisioning profile.
public struct ProvisioningProfile: Equatable, Sendable {
    public let expirationDate: Date
    /// `get-task-allow`, which development profiles grant and ad hoc ones don't.
    public let allowsDebugging: Bool

    /// The profile is a CMS signed message with its property list stored whole inside, and iOS has no
    /// API to open CMS, so the property list is cut out from between its first and last lines.
    public init?(data: Data) {
        guard let start = data.firstRange(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), options: .backwards, in: start.upperBound ..< data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound ..< end.upperBound], format: nil),
              let dictionary = plist as? [String: Any],
              let expirationDate = dictionary["ExpirationDate"] as? Date
        else { return nil }
        self.expirationDate = expirationDate
        let entitlements = dictionary["Entitlements"] as? [String: Any]
        allowsDebugging = entitlements?["get-task-allow"] as? Bool ?? false
    }
}
