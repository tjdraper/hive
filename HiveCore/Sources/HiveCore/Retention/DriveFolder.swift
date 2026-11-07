import Darwin
import Foundation

enum DriveFolderError: Error, Equatable {
    case couldNotOpen(errno: Int32)
    case couldNotRead(errno: Int32)
    case couldNotRemove(errno: Int32)
    /// Something is on another volume, which nothing in a snapshot ever is.
    case otherVolume
}

/// The space a tree takes on the drive, with each file counted once however many links it has.
struct SpaceTally {
    struct LinkedFile {
        let bytes: Int64
        let links: Int
        var linksHere: Int
    }

    /// Folders, and files with a single link.
    var singleBytes: Int64 = 0
    /// Files with more than one link, by inode.
    var linked: [UInt64: LinkedFile] = [:]

    /// What removing the tree would free: everything with no link outside it.
    var exclusiveBytes: Int64 {
        linked.values.reduce(singleBytes) { $1.linksHere >= $1.links ? $0 + $1.bytes : $0 }
    }
}

/// A folder on the backup drive, held open and worked on only through file descriptors opened without
/// following symbolic links, so nothing a server sent can lead outside it. Links inside are removed,
/// never followed. A folder that lacks its owner's permissions gets them back before Hive goes in: a
/// server's folder may arrive read-only, and the folder's own mode isn't what keeps the server's, since
/// `--fake-super` keeps that in an attribute.
final class DriveFolder {
    let descriptor: Int32
    let device: dev_t

    /// The drive's `Hive` folder, which has to be a real folder.
    init(at url: URL) throws {
        let descriptor = open(url.fileSystemPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw DriveFolderError.couldNotOpen(errno: errno) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            close(descriptor)
            throw DriveFolderError.couldNotOpen(errno: errno)
        }
        self.descriptor = descriptor
        device = info.st_dev
    }

    /// The real folder `name` within `parent`, on the same volume. `name` is one name, never a path,
    /// since the system would follow a link anywhere along a path.
    init(name: String, in parent: DriveFolder) throws {
        guard Self.isOneName(name) else { throw DriveFolderError.couldNotOpen(errno: EINVAL) }
        let name = Array(name.utf8CString)
        let info = try Self.status(of: name, in: parent.descriptor, device: parent.device)
        guard info.st_mode & S_IFMT == S_IFDIR else { throw DriveFolderError.couldNotOpen(errno: ENOTDIR) }
        descriptor = try Self.openFolder(name, in: parent.descriptor, info: info)
        device = info.st_dev
    }

    deinit {
        close(descriptor)
    }

    static func isOneName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }

    /// Whether anything at all, even a link, has `name` here.
    func contains(_ name: String) throws -> Bool {
        guard Self.isOneName(name) else { throw DriveFolderError.couldNotRead(errno: EINVAL) }
        var info = stat()
        if fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 { return true }
        guard errno == ENOENT else { throw DriveFolderError.couldNotRead(errno: errno) }
        return false
    }

    /// Fails when anything already has the new name.
    func rename(_ name: String, to newName: String) throws {
        guard Self.isOneName(name), Self.isOneName(newName) else { throw DriveFolderError.couldNotRemove(errno: EINVAL) }
        guard renameatx_np(descriptor, name, descriptor, newName, UInt32(RENAME_EXCL)) == 0 else {
            throw DriveFolderError.couldNotRemove(errno: errno)
        }
    }

    /// Removes the folder `name` and everything in it. Stops between entries when the task is cancelled,
    /// leaving the rest for later.
    func removeFolder(_ name: String) throws {
        let folder = try DriveFolder(name: name, in: self)
        try Self.removeContents(of: folder.descriptor, device: folder.device)
        guard unlinkat(descriptor, name, AT_REMOVEDIR) == 0 else { throw DriveFolderError.couldNotRemove(errno: errno) }
    }

    func tally() throws -> SpaceTally {
        var tally = SpaceTally()
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw DriveFolderError.couldNotRead(errno: errno) }
        tally.singleBytes += Int64(info.st_blocks) * 512
        try Self.tallyContents(of: descriptor, device: device, into: &tally)
        return tally
    }

    private static func tallyContents(of folder: Int32, device: dev_t, into tally: inout SpaceTally) throws {
        for name in try entries(of: folder) {
            try Task.checkCancellation()
            let info = try status(of: name, in: folder, device: device)
            let bytes = Int64(info.st_blocks) * 512
            if info.st_mode & S_IFMT == S_IFDIR {
                tally.singleBytes += bytes
                let child = try openFolder(name, in: folder, info: info)
                defer { close(child) }
                try tallyContents(of: child, device: device, into: &tally)
            } else if info.st_nlink <= 1 {
                tally.singleBytes += bytes
            } else {
                let file = SpaceTally.LinkedFile(bytes: bytes, links: Int(info.st_nlink), linksHere: 0)
                tally.linked[UInt64(info.st_ino), default: file].linksHere += 1
            }
        }
    }

    private static func removeContents(of folder: Int32, device: dev_t) throws {
        for name in try entries(of: folder) {
            try Task.checkCancellation()
            let info = try status(of: name, in: folder, device: device)
            if info.st_mode & S_IFMT == S_IFDIR {
                let child = try openFolder(name, in: folder, info: info)
                defer { close(child) }
                try removeContents(of: child, device: device)
                guard unlinkat(folder, name, AT_REMOVEDIR) == 0 else { throw DriveFolderError.couldNotRemove(errno: errno) }
            } else {
                guard unlinkat(folder, name, 0) == 0 else { throw DriveFolderError.couldNotRemove(errno: errno) }
            }
        }
    }

    private static func status(of name: [CChar], in folder: Int32, device: dev_t) throws -> stat {
        var info = stat()
        guard fstatat(folder, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw DriveFolderError.couldNotRead(errno: errno) }
        guard info.st_dev == device else { throw DriveFolderError.otherVolume }
        return info
    }

    /// Gives the folder its owner's read, write and search permissions when it lacks any, then opens it.
    /// Its owner is Hive's user, since rsync made it, and a folder is never hard linked, so this changes
    /// nothing in any other snapshot.
    private static func openFolder(_ name: [CChar], in parent: Int32, info: stat) throws -> Int32 {
        if info.st_mode & S_IRWXU != S_IRWXU {
            guard fchmodat(parent, name, (info.st_mode & 0o7777) | S_IRWXU, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw DriveFolderError.couldNotOpen(errno: errno)
            }
        }
        let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw DriveFolderError.couldNotOpen(errno: errno) }
        // The folder that was checked, not something put in its place since.
        var opened = stat()
        guard fstat(descriptor, &opened) == 0, opened.st_ino == info.st_ino, opened.st_dev == info.st_dev else {
            close(descriptor)
            throw DriveFolderError.couldNotOpen(errno: EAGAIN)
        }
        return descriptor
    }

    /// Every name in the folder but `.` and `..`, as bytes ending in a zero, since a name needn't be
    /// valid UTF-8.
    private static func entries(of folder: Int32) throws -> [[CChar]] {
        let copy = dup(folder)
        guard copy >= 0 else { throw DriveFolderError.couldNotRead(errno: errno) }
        guard let directory = fdopendir(copy) else {
            close(copy)
            throw DriveFolderError.couldNotRead(errno: errno)
        }
        defer { closedir(directory) }
        // The copy shares its place with `folder`, which may have been read before.
        rewinddir(directory)

        var names: [[CChar]] = []
        errno = 0
        while let entry = readdir(directory) {
            let length = Int(entry.pointee.d_namlen)
            let name = withUnsafeBytes(of: entry.pointee.d_name) { bytes in
                bytes.prefix(length).map { CChar(bitPattern: $0) } + [0]
            }
            if name != [46, 0], name != [46, 46, 0] { names.append(name) }
        }
        guard errno == 0 else { throw DriveFolderError.couldNotRead(errno: errno) }
        return names
    }
}
