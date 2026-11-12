import Foundation
import HiveKit

enum DaemonInfoError: Error {
    case missing(key: String)
}

/// The daemon's version, and names that differ between the installed daemon and the development one. The
/// build writes the names into the daemon's Info.plist from the bundle ID prefix (Configuration/HiveDaemon-Info.plist).
struct DaemonInfo {
    let pairingMachService: String
    let beekeeperSigningIdentifier: String
    let version: ReleaseVersion?

    static func read(from bundle: Bundle = .main) throws -> DaemonInfo {
        DaemonInfo(
            pairingMachService: try value(for: "HivePairingMachService", in: bundle),
            beekeeperSigningIdentifier: try value(for: "HiveBeekeeperSigningIdentifier", in: bundle),
            version: (try? value(for: "CFBundleShortVersionString", in: bundle)).flatMap(ReleaseVersion.init)
        )
    }

    private static func value(for key: String, in bundle: Bundle) throws -> String {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            throw DaemonInfoError.missing(key: key)
        }
        return value
    }
}
