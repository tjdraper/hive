#if os(macOS)
import Foundation

enum LocalHiveServiceError: Error {
    case missing(key: String)
}

/// How to reach this Mac's Hive over XPC. The build writes the names into Beekeeper's Info.plist from the
/// bundle ID prefix (Configuration/Beekeeper-Info.plist), so a Debug Beekeeper reaches the development daemon.
struct LocalHiveService {
    let machService: String
    /// Beekeeper only talks to a daemon signed by its own team with this identifier. Anything running as
    /// you can register a Mach service of the same name for your login session, and would otherwise
    /// receive the pairing and hand back its own key to pin.
    let daemonSigningIdentifier: String

    static func read(from bundle: Bundle = .main) throws -> LocalHiveService {
        LocalHiveService(
            machService: try value(for: "HivePairingMachService", in: bundle),
            daemonSigningIdentifier: try value(for: "HiveDaemonSigningIdentifier", in: bundle)
        )
    }

    private static func value(for key: String, in bundle: Bundle) throws -> String {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            throw LocalHiveServiceError.missing(key: key)
        }
        return value
    }
}
#endif
