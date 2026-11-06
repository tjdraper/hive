import Foundation

enum DaemonInfoError: Error {
    case missing(key: String)
}

/// Names that differ between the installed daemon and the development one. The build writes them into
/// the daemon's Info.plist from the bundle ID prefix (Configuration/HiveDaemon-Info.plist).
struct DaemonInfo {
    let pairingMachService: String
    let beekeeperSigningIdentifier: String

    static func read(from bundle: Bundle = .main) throws -> DaemonInfo {
        DaemonInfo(
            pairingMachService: try value(for: "HivePairingMachService", in: bundle),
            beekeeperSigningIdentifier: try value(for: "HiveBeekeeperSigningIdentifier", in: bundle)
        )
    }

    private static func value(for key: String, in bundle: Bundle) throws -> String {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            throw DaemonInfoError.missing(key: key)
        }
        return value
    }
}
