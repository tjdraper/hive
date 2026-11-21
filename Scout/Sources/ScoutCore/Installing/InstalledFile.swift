#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

public enum InstalledFileError: Error, Equatable {
    case couldNotRead(path: String, errno: Int32)
    case couldNotWrite(path: String, errno: Int32)
    case couldNotRemove(path: String, errno: Int32)
}

/// A file installing writes as root, in a folder only root can write: Scout's binary, its service
/// and its management rule. Each is written beside itself and renamed into place, so a server is
/// never left with half of one.
enum InstalledFile {
    /// Whether `path` holds exactly `bytes`.
    static func holds(_ bytes: [UInt8], at path: String) -> Bool {
        (try? contents(of: path)) == bytes
    }

    static func contents(of path: String) throws(InstalledFileError) -> [UInt8] {
        let descriptor = open(path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw .couldNotRead(path: path, errno: errno) }
        defer { SystemFiles.close(descriptor) }
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw .couldNotRead(path: path, errno: errno) }
            guard count > 0 else { return bytes }
            bytes += buffer[..<count]
        }
    }

    /// Writes `bytes` to a file beside `path`, for checking before it's put in place.
    static func stage(_ bytes: [UInt8], for path: String, mode: mode_t) throws(InstalledFileError) -> String {
        let staged = path + ".new"
        let descriptor = open(staged, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC, mode)
        guard descriptor >= 0 else { throw .couldNotWrite(path: staged, errno: errno) }
        defer { SystemFiles.close(descriptor) }
        var remaining = bytes[...]
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            if written < 0, errno == EINTR { continue }
            guard written > 0 else { unlink(staged); throw .couldNotWrite(path: staged, errno: errno) }
            remaining = remaining.dropFirst(written)
        }
        // A file left from before keeps its old mode through O_CREAT.
        guard fchmod(descriptor, mode) == 0, fsync(descriptor) == 0 else {
            unlink(staged)
            throw .couldNotWrite(path: staged, errno: errno)
        }
        return staged
    }

    static func putInPlace(_ staged: String, at path: String) throws(InstalledFileError) {
        guard rename(staged, path) == 0 else {
            unlink(staged)
            throw .couldNotWrite(path: path, errno: errno)
        }
    }

    /// Writes `bytes` to `path` unless it already holds them, and says whether it did.
    static func replace(_ path: String, with bytes: [UInt8], mode: mode_t) throws(InstalledFileError) -> Bool {
        guard !holds(bytes, at: path) else { return false }
        try putInPlace(stage(bytes, for: path, mode: mode), at: path)
        return true
    }

    /// Removes `path`, and says whether it was there.
    @discardableResult
    static func remove(_ path: String) throws(InstalledFileError) -> Bool {
        guard unlink(path) == 0 else {
            if errno == ENOENT { return false }
            throw .couldNotRemove(path: path, errno: errno)
        }
        return true
    }
}
