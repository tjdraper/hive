import ScoutProtocol

/// Scout's own version, raised only when Scout changes, apart from Hive's.
public enum ScoutRelease {
    public static let version = ScoutVersion(0, 2, 0)

    /// The system and CPU this binary was built for, which Hive records so it knows which to install.
    public static var platform: String {
        #if os(Linux)
        let system = "linux"
        #elseif os(macOS)
        let system = "macos"
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
    }
}
