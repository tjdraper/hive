import Darwin
import Foundation

public struct RecordedUser: Codable, Equatable, Sendable {
    public let userID: uid_t

    public init(userID: uid_t) {
        self.userID = userID
    }
}

public enum RecordedUserStoreError: Error, Equatable {
    case notProtected
    case unreadable(errno: Int32)
    case malformed
    case unwritable(errno: Int32)
}

/// The system daemon becomes whichever account this file names, so it's only trusted while nobody
/// but its owner can change it or the folder holding it.
public struct RecordedUserStore: Sendable {
    public static let systemDirectory = URL(filePath: "/Library/Application Support/Hive", directoryHint: .isDirectory)

    let directory: URL
    /// Root for the installed daemon. Tests pass their own user ID, since they can't create files owned by root.
    let owner: uid_t

    public init(directory: URL = Self.systemDirectory, owner: uid_t = 0) {
        self.directory = directory
        self.owner = owner
    }

    var fileURL: URL {
        directory.appending(path: "recorded-user.json", directoryHint: .notDirectory)
    }

    public func read() throws -> RecordedUser? {
        guard try checkDirectory() else { return nil }

        let descriptor = open(fileURL.fileSystemPath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor == -1 {
            if errno == ENOENT { return nil }
            if errno == ELOOP { throw RecordedUserStoreError.notProtected }
            throw RecordedUserStoreError.unreadable(errno: errno)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)

        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw RecordedUserStoreError.unreadable(errno: errno) }
        guard info.st_mode & S_IFMT == S_IFREG, isProtected(info) else { throw RecordedUserStoreError.notProtected }

        let data: Data
        do {
            data = try handle.readToEnd() ?? Data()
        } catch {
            throw RecordedUserStoreError.unreadable(errno: EIO)
        }
        guard let user = try? JSONDecoder().decode(RecordedUser.self, from: data) else {
            throw RecordedUserStoreError.malformed
        }
        return user
    }

    public func write(_ user: RecordedUser) throws {
        if mkdir(directory.fileSystemPath, 0o700) != 0, errno != EEXIST {
            throw RecordedUserStoreError.unwritable(errno: errno)
        }
        guard try checkDirectory() else { throw RecordedUserStoreError.unwritable(errno: ENOENT) }

        do {
            try JSONEncoder().encode(user).write(to: fileURL, options: .atomic)
        } catch {
            throw RecordedUserStoreError.unwritable(errno: EIO)
        }
        guard chmod(fileURL.fileSystemPath, 0o600) == 0 else {
            throw RecordedUserStoreError.unwritable(errno: errno)
        }
    }

    public func clear() throws {
        guard try checkDirectory() else { return }
        if unlink(fileURL.fileSystemPath) != 0, errno != ENOENT {
            throw RecordedUserStoreError.unwritable(errno: errno)
        }
    }

    /// Returns false when the folder doesn't exist yet.
    private func checkDirectory() throws -> Bool {
        var info = stat()
        if lstat(directory.fileSystemPath, &info) != 0 {
            if errno == ENOENT { return false }
            throw RecordedUserStoreError.unreadable(errno: errno)
        }
        guard info.st_mode & S_IFMT == S_IFDIR, isProtected(info) else { throw RecordedUserStoreError.notProtected }
        return true
    }

    private func isProtected(_ info: stat) -> Bool {
        info.st_uid == owner && info.st_mode & (S_IWGRP | S_IWOTH) == 0
    }
}
