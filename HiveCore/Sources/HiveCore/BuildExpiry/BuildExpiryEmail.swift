import Foundation
import HiveKit

/// The email for a build expiry warning (§16).
enum BuildExpiryEmail {
    enum Problem: Error {
        /// Only a build with an expiry is warned about.
        case noExpiry
    }

    static func message(deviceName: String, build: BeekeeperBuild, warning: BuildExpiryWarning, text: AlertText) throws -> EmailMessage {
        guard let expiresAt = build.expiresAt else { throw Problem.noExpiry }
        let beekeeper = "Beekeeper \(build.version) (\(build.build)) on “\(deviceName)”"
        let date = text.date(expiresAt)
        let (explanation, action) = switch build.distribution {
        case .testFlight:
            ("\(beekeeper) is a TestFlight build, which stops opening on \(date).", "Install a newer build from TestFlight before then.")
        case .adHoc:
            (
                "\(beekeeper) is an ad hoc build, which stops opening when its provisioning profile expires on \(date).",
                "Install a newer build before then."
            )
        case .development, .developerID:
            (
                "\(beekeeper) was installed from Xcode, and stops opening when its provisioning profile expires on \(date).",
                "Build and install it again before then."
            )
        }
        let lines = [
            explanation,
            "",
            "\(action) If a newer build is already on it, open Beekeeper there once, so Hive knows.",
            "",
            warning == .threeDays ? "This is the last warning about this build." : "You'll get one more warning 3 days before it expires.",
            "Each Hive the device is paired with sends these warnings, unless they're turned off in its settings.",
        ]
        let subject = "Beekeeper on “\(deviceName)” expires on \(text.day(expiresAt))"
        return EmailMessage(subject: warning == .threeDays ? "Last warning: \(subject)" : subject, body: lines.joined(separator: "\n"))
    }
}
