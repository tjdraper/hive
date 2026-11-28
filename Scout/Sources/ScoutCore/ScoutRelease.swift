#if canImport(Darwin)
import Darwin
#endif
import ScoutProtocol

/// Scout's own version, raised only when Scout changes, apart from Hive's.
public enum ScoutRelease {
    public static let version = ScoutVersion(0, 3, 0)

    /// The system and CPU this binary was built for, which Hive records so it knows which to install.
    /// A Mac's release is one universal binary for both CPUs.
    public static var platform: String {
        #if os(macOS)
        return "macos-universal"
        #else
        #if os(Linux)
        let system = "linux"
        #else
        let system = "other"
        #endif
        #if arch(x86_64)
        return "\(system)-x86_64"
        #elseif arch(arm64)
        return "\(system)-aarch64"
        #else
        return "\(system)-other"
        #endif
        #endif
    }

    /// The running binary, which installing copies and runs again.
    public static var executablePath: String {
        #if os(macOS)
        // PROC_PIDPATHINFO_MAXSIZE, which Swift doesn't import.
        var path = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(getpid(), &path, UInt32(path.count))
        guard length > 0 else { return "" }
        return String(validating: path[..<Int(length)], as: UTF8.self) ?? ""
        #else
        return "/proc/self/exe"
        #endif
    }
}
