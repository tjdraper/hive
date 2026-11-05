import Darwin
import Foundation

public enum InstalledBundleError: Error, Equatable {
    case notProtected
    case linkLeavesBundle
    case unreadable(errno: Int32)
}

/// launchd starts the daemon as root from whatever is in Hive.app when it was registered, and macOS
/// doesn't stop the user's own programs from changing a bundle they own. So the system daemon only
/// runs from a bundle that root owns and only root can change.
public struct InstalledBundleCheck {
    let bundle: URL
    /// Root for the installed daemon. Tests pass their own user ID, since they can't create files owned by root.
    let owner: uid_t

    public init(bundle: URL, owner: uid_t = 0) {
        self.bundle = bundle
        self.owner = owner
    }

    /// The app bundle holding this executable, at Contents/MacOS inside it.
    public static func forCurrentExecutable() -> InstalledBundleCheck? {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return InstalledBundleCheck(bundle: bundle)
    }

    public func verify() throws {
        let root = bundle.resolvingSymlinksInPath().fileSystemPath
        try check(root, bundleRoot: root)

        let contents: [String]
        do {
            contents = try FileManager.default.subpathsOfDirectory(atPath: root)
        } catch {
            throw InstalledBundleError.unreadable(errno: EIO)
        }
        for item in contents {
            try check(root + "/" + item, bundleRoot: root)
        }
    }

    private func check(_ path: String, bundleRoot: String) throws {
        var info = stat()
        guard lstat(path, &info) == 0 else { throw InstalledBundleError.unreadable(errno: errno) }
        guard info.st_uid == owner, info.st_mode & (S_IWGRP | S_IWOTH) == 0 else {
            throw InstalledBundleError.notProtected
        }
        if info.st_mode & S_IFMT == S_IFLNK {
            let target = URL(filePath: path).resolvingSymlinksInPath().fileSystemPath
            guard target.hasPrefix(bundleRoot + "/") else { throw InstalledBundleError.linkLeavesBundle }
        }
    }
}
