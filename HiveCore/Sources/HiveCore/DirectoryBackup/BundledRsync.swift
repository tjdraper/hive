import Foundation

/// The rsync built by `Scripts/build-rsync.sh` and embedded beside the daemon in Hive.app's
/// `Contents/MacOS`, which only root can change (§4, §11).
public enum BundledRsync {
    public static func url(besideExecutable executable: URL) -> URL {
        executable.resolvingSymlinksInPath().deletingLastPathComponent().appending(path: "rsync", directoryHint: .notDirectory)
    }

    public static func isPresent(at url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.fileSystemPath)
    }
}
