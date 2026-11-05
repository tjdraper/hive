import Darwin
import Foundation

public enum DataDirectoryError: Error, Equatable {
    case couldNotCreate(errno: Int32)
    case notADirectory
    case ownedByAnotherUser
    case couldNotRestrict(errno: Int32)
}

/// Hive's data folder in the account's own Library, so the Mac's regular backup includes it.
public struct DataDirectoryBuilder {
    public init() {}

    public func prepare(named name: String, for account: UserAccount) throws -> URL {
        let applicationSupport = account.homeDirectory.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let directory = applicationSupport.appending(path: name, directoryHint: .isDirectory)
        let path = directory.fileSystemPath

        do {
            try FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        } catch {
            throw DataDirectoryError.couldNotCreate(errno: EIO)
        }
        if mkdir(path, 0o700) != 0, errno != EEXIST {
            throw DataDirectoryError.couldNotCreate(errno: errno)
        }

        var info = stat()
        guard lstat(path, &info) == 0 else { throw DataDirectoryError.couldNotCreate(errno: errno) }
        guard info.st_mode & S_IFMT == S_IFDIR else { throw DataDirectoryError.notADirectory }
        guard info.st_uid == account.userID else { throw DataDirectoryError.ownedByAnotherUser }
        guard chmod(path, 0o700) == 0 else { throw DataDirectoryError.couldNotRestrict(errno: errno) }

        return directory
    }
}
