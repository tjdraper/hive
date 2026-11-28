#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

public enum PrivateFileError: Error, Equatable {
    case couldNotOpen(path: String, errno: Int32)
    case couldNotWrite(path: String, errno: Int32)
    case couldNotRead(path: String, errno: Int32)
    case tooLarge(path: String)
}

/// A file only its owner can read, such as the one holding Scout's key. It's replaced whole, through a
/// file beside it renamed into place, so a failure part way never leaves half of one.
enum PrivateFile {
    /// Far larger than anything Scout keeps in one.
    static let largest = 64 * 1024

    /// Nil when there's no file. A symbolic link is refused rather than followed.
    static func read(_ path: String) throws -> [UInt8]? {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw PrivateFileError.couldNotOpen(path: path, errno: errno)
        }
        defer { SystemFiles.close(descriptor) }
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { systemRead(descriptor, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw PrivateFileError.couldNotRead(path: path, errno: errno) }
            guard count > 0 else { return bytes }
            bytes += buffer[..<count]
            guard bytes.count <= largest else { throw PrivateFileError.tooLarge(path: path) }
        }
    }

    /// - Parameter synced: whether it's on the disk before it's renamed into place, for what a crash
    ///   mustn't lose, such as Scout's key.
    static func write(_ bytes: [UInt8], to path: String, synced: Bool = true) throws {
        let staged = path + ".new"
        do {
            try writeStaged(bytes, to: staged, synced: synced)
            guard rename(staged, path) == 0 else { throw PrivateFileError.couldNotWrite(path: path, errno: errno) }
        } catch {
            unlink(staged)
            throw error
        }
    }

    /// Whether a file can be written beside `path`, so work that can't be undone, such as enrolling,
    /// isn't done only to find its result can't be kept.
    static func checkWritable(beside path: String) throws {
        let staged = path + ".new"
        try writeStaged([], to: staged, synced: true)
        unlink(staged)
    }

    private static func writeStaged(_ bytes: [UInt8], to path: String, synced: Bool) throws {
        // Not created by following a link someone else left in its place.
        let descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw PrivateFileError.couldNotOpen(path: path, errno: errno) }
        defer { SystemFiles.close(descriptor) }
        // A file left from before keeps its old mode through O_CREAT.
        guard fchmod(descriptor, 0o600) == 0 else { throw PrivateFileError.couldNotWrite(path: path, errno: errno) }
        var remaining = bytes[...]
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { systemWrite(descriptor, $0.baseAddress, $0.count) }
            if written < 0, errno == EINTR { continue }
            guard written > 0 else { throw PrivateFileError.couldNotWrite(path: path, errno: errno) }
            remaining = remaining.dropFirst(written)
        }
        guard !synced || fsync(descriptor) == 0 else { throw PrivateFileError.couldNotWrite(path: path, errno: errno) }
    }

    private static func systemRead(_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.read(descriptor, buffer, count)
        #elseif canImport(Glibc)
        Glibc.read(descriptor, buffer, count)
        #else
        Musl.read(descriptor, buffer, count)
        #endif
    }

    private static func systemWrite(_ descriptor: Int32, _ buffer: UnsafeRawPointer?, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.write(descriptor, buffer, count)
        #elseif canImport(Glibc)
        Glibc.write(descriptor, buffer, count)
        #else
        Musl.write(descriptor, buffer, count)
        #endif
    }
}
