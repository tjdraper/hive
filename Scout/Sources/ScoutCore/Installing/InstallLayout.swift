/// Where an installed Scout's files go, as the server sees them. Tests put them under a temporary
/// folder with `root`.
public struct InstallLayout: Sendable {
    public static let server = Self(root: "/")

    /// The user Scout runs as, which owns its state folder.
    public static let user = "hive-scout"

    let root: String
    var binary = "/usr/local/bin/hive-scout"
    var systemdUnit = "/etc/systemd/system/hive-scout.service"
    var openRCScript = "/etc/init.d/hive-scout"
    var sudoRule = "/etc/sudoers.d/hive-scout"
    var doasRule = "/etc/doas.d/hive-scout.conf"
    var stateDirectory = EnrollmentStore.defaultDirectory
    /// Under `/run`, which systemd's `RuntimeDirectory` needs.
    var runtimeDirectory = SendingStatusFile.defaultDirectory

    init(root: String) {
        self.root = root.hasSuffix("/") ? String(root.dropLast()) : root
    }

    /// Where `path` is on this machine's disk.
    func onDisk(_ path: String) -> String {
        root + path
    }
}
