/// Where an installed Scout's files go, as the server sees them. Tests put them under a temporary
/// folder with `root`.
public struct InstallLayout: Sendable {
    public enum System: Sendable {
        case linux
        case mac
    }

    #if os(macOS)
    public static let server = Self(root: "/", system: .mac)
    #else
    public static let server = Self(root: "/", system: .linux)
    #endif

    let root: String
    let system: System
    /// The user Scout runs as, which owns its state folder. A Mac's system users start with `_`.
    public let user: String
    var binary = "/usr/local/bin/hive-scout"
    var systemdUnit = "/etc/systemd/system/hive-scout.service"
    var openRCScript = "/etc/init.d/hive-scout"
    var launchDaemon = "/Library/LaunchDaemons/\(Self.launchdLabel).plist"
    var sudoRule = "/etc/sudoers.d/hive-scout"
    var doasRule = "/etc/doas.d/hive-scout.conf"
    public let stateDirectory: String
    /// Under `/run` on Linux, which systemd's `RuntimeDirectory` needs. A Mac has no folder kept in
    /// memory, so its status goes in the state folder.
    public let runtimeDirectory: String

    /// Fixed, as Hive's own log subsystems are, so it doesn't depend on the bundle ID prefix a build uses.
    static let launchdLabel = "com.buzzingpixel.hive-scout"

    init(root: String, system: System = .linux) {
        self.root = root.hasSuffix("/") ? String(root.dropLast()) : root
        self.system = system
        switch system {
        case .linux:
            user = "hive-scout"
            stateDirectory = "/var/lib/hive-scout"
            runtimeDirectory = "/run/hive-scout"
        case .mac:
            user = "_hive-scout"
            stateDirectory = "/Library/Application Support/Hive Scout"
            runtimeDirectory = stateDirectory
        }
    }

    /// Where `path` is on this machine's disk.
    func onDisk(_ path: String) -> String {
        root + path
    }
}
