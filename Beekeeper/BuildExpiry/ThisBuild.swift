import Foundation
import HiveKit
#if os(iOS)
import UIKit
#endif

/// The build of Beekeeper running here, as it reports itself to each Hive it signs in to (§16).
enum ThisBuild {
    static let current: BeekeeperBuild = {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        #if os(macOS)
        #if DEBUG
        let distribution = BuildDistribution.development
        #else
        let distribution = BuildDistribution.developerID
        #endif
        return BeekeeperBuild(platform: .mac, version: version, build: build, distribution: distribution, expiresAt: nil)
        #else
        let platform: BeekeeperPlatform = UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #if targetEnvironment(simulator)
        // A simulator build has no provisioning profile, which would otherwise make it TestFlight's.
        return BeekeeperBuild(platform: platform, version: version, build: build, distribution: .development, expiresAt: nil)
        #else
        let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision").flatMap { try? Data(contentsOf: $0) }
        return BuildExpiryResolver.mobileBuild(
            platform: platform,
            version: version,
            build: build,
            provisioningProfile: profile,
            buildDate: info["BeekeeperBuildDate"] as? String
        )
        #endif
        #endif
    }()
}
