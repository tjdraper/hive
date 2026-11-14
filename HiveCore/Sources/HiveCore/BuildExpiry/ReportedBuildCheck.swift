import Foundation
import HiveKit

/// A build a device reports is stored, listed and emailed, so it's checked first. One that fails is
/// left out, and the sign-in goes ahead.
enum ReportedBuildCheck {
    /// Far longer than any version or build number Beekeeper has.
    static let longest = 32
    private static let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_+")

    static func validated(_ build: BeekeeperBuild?) -> BeekeeperBuild? {
        guard let build, isValid(build.version), isValid(build.build) else { return nil }
        return build
    }

    private static func isValid(_ text: String) -> Bool {
        !text.isEmpty && text.count <= longest && text.allSatisfy(allowed.contains)
    }
}
