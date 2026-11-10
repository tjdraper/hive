import Darwin
import Foundation

public enum OwnerOnlyFileError: Error, Equatable {
    case notProtected
    case unreadable(errno: Int32)
    case unwritable(errno: Int32)
    case alreadyExists
}

/// A small file only its owner can read or change, written whole or not at all.
struct OwnerOnlyFile {
    let url: URL
    let owner: uid_t

    init(url: URL, owner: uid_t = geteuid()) {
        self.url = url
        self.owner = owner
    }

    private var partialPath: String {
        url.fileSystemPath + ".partial"
    }

    /// Returns nil when there's no file.
    func read() throws -> Data? {
        let descriptor = open(url.fileSystemPath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor == -1 {
            if errno == ENOENT { return nil }
            if errno == ELOOP { throw OwnerOnlyFileError.notProtected }
            throw OwnerOnlyFileError.unreadable(errno: errno)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)

        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw OwnerOnlyFileError.unreadable(errno: errno) }
        guard info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == owner,
              info.st_mode & (S_IRWXG | S_IRWXO) == 0
        else { throw OwnerOnlyFileError.notProtected }

        do {
            return try handle.readToEnd() ?? Data()
        } catch {
            throw OwnerOnlyFileError.unreadable(errno: EIO)
        }
    }

    /// Never replaces an existing file. A crash part way leaves only a partial file, which the next
    /// attempt removes, so a half-written file is never read back as whole.
    func create(_ data: Data) throws {
        try write(data, replacing: false)
    }

    /// Replaces the file whole, so a crash part way leaves the old one.
    func replace(_ data: Data) throws {
        try write(data, replacing: true)
    }

    private func write(_ data: Data, replacing: Bool) throws {
        if unlink(partialPath) != 0, errno != ENOENT { throw OwnerOnlyFileError.unwritable(errno: errno) }

        let descriptor = open(partialPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor != -1 else { throw OwnerOnlyFileError.unwritable(errno: errno) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)

        do {
            guard fchmod(descriptor, 0o600) == 0 else { throw OwnerOnlyFileError.unwritable(errno: errno) }
            try handle.write(contentsOf: data)
            guard fsync(descriptor) == 0 else { throw OwnerOnlyFileError.unwritable(errno: errno) }
            try handle.close()
        } catch {
            unlink(partialPath)
            throw error as? OwnerOnlyFileError ?? .unwritable(errno: EIO)
        }

        if renamex_np(partialPath, url.fileSystemPath, replacing ? 0 : UInt32(RENAME_EXCL)) != 0 {
            let renameError = errno
            unlink(partialPath)
            if renameError == EEXIST { throw OwnerOnlyFileError.alreadyExists }
            throw OwnerOnlyFileError.unwritable(errno: renameError)
        }
    }

    func remove() throws {
        if unlink(url.fileSystemPath) != 0, errno != ENOENT { throw OwnerOnlyFileError.unwritable(errno: errno) }
    }
}
