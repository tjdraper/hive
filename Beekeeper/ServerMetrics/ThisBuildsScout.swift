import Foundation
import HiveKit

/// The Scout release built into this Beekeeper, which every command it shows installs (A5).
enum ThisBuildsScout {
    /// Nil in a build with no download address, which only a release has.
    static let release: ScoutRelease? = {
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ key: String) -> String {
            info[key] as? String ?? ""
        }
        return ScoutRelease(
            version: value("ScoutVersion"),
            downloadFolder: value("ScoutDownloadURL"),
            sha256X86: value("ScoutSHA256LinuxX86_64"),
            sha256Arm: value("ScoutSHA256LinuxAarch64")
        )
    }()

    /// The kind of CPU a Scout reported, such as `linux-aarch64`, to show its command first.
    static func platform(reportedAs reported: String?) -> ScoutRelease.Platform? {
        ScoutRelease.Platform.allCases.first { reported == "linux-\($0.cpu)" }
    }
}
