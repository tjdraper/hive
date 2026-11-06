import Darwin
import Foundation

enum RealFolderError: Error, Equatable {
    case notARealFolder
    case invalidName
    case couldNotCreate(errno: Int32)
}

/// Folders Hive writes into on the backup drive. Every part of the path below the drive's `Hive`
/// folder has to be a real folder, never a symbolic link, so nothing written into a snapshot can land
/// outside it, whatever a server sent before.
enum RealFolder {
    static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.fileSystemPath, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    /// Makes each of `parts` in turn under `base`, which has to be a real folder already, and checks
    /// each one it finds or makes.
    @discardableResult
    static func make(_ parts: [String], under base: URL) throws -> URL {
        guard exists(base) else { throw RealFolderError.notARealFolder }
        var url = base
        for part in parts {
            guard !part.isEmpty, part != ".", part != "..", !part.contains("/") else { throw RealFolderError.invalidName }
            url = url.appending(path: part, directoryHint: .isDirectory)
            if mkdir(url.fileSystemPath, 0o755) != 0, errno != EEXIST {
                throw RealFolderError.couldNotCreate(errno: errno)
            }
            guard exists(url) else { throw RealFolderError.notARealFolder }
        }
        return url
    }

    /// The folder `parts` names under `base`, when every part of it is a real folder.
    static func existing(_ parts: [String], under base: URL) -> URL? {
        var url = base
        guard exists(url) else { return nil }
        for part in parts {
            guard !part.isEmpty, part != ".", part != "..", !part.contains("/") else { return nil }
            url = url.appending(path: part, directoryHint: .isDirectory)
            guard exists(url) else { return nil }
        }
        return url
    }
}
