import Foundation

/// The build of Beekeeper a device runs, which it reports each time it signs in, so Hive can warn
/// before an iPhone or iPad build stops opening (§16).
public struct BeekeeperBuild: Codable, Hashable, Sendable {
    public let platform: BeekeeperPlatform
    /// `CFBundleShortVersionString`, such as 2026.3.
    public let version: String
    /// `CFBundleVersion`, which goes up with every TestFlight upload.
    public let build: String
    public let distribution: BuildDistribution
    /// Nil for a build that never expires, or one whose expiry Beekeeper couldn't work out.
    public let expiresAt: Date?

    public init(platform: BeekeeperPlatform, version: String, build: String, distribution: BuildDistribution, expiresAt: Date?) {
        self.platform = platform
        self.version = version
        self.build = build
        self.distribution = distribution
        self.expiresAt = expiresAt
    }
}

public enum BeekeeperPlatform: String, Codable, Hashable, Sendable {
    case mac
    case iPhone
    case iPad
}

public enum BuildDistribution: String, Codable, Hashable, Sendable {
    /// A Mac build. It never expires.
    case developerID
    /// Stops opening 90 days after upload.
    case testFlight
    /// Stops opening when its provisioning profile expires.
    case adHoc
    /// Built and installed from Xcode. An iPhone or iPad build stops opening when its provisioning
    /// profile expires, after 7 days for a free Apple account.
    case development
}
