#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// Reads the kernel's text files, such as those in `/proc` and `/sys`, under a root folder: `/` on a
/// server, and a folder of files captured from a real one in tests.
public struct SystemFiles: Sendable {
    public let root: String

    public init(root: String = "/") {
        self.root = root.hasSuffix("/") ? String(root.dropLast()) : root
    }

    /// The file's text, or nil when it doesn't exist or can't be read, such as a process that has
    /// already exited.
    public func text(at path: String) -> String? {
        guard let (descriptor, _) = openFile(path) else { return nil }
        defer { Self.close(descriptor) }
        var buffer = [UInt8](repeating: 0, count: 4096)
        guard let count = Self.readFromStart(descriptor, into: &buffer) else { return nil }
        // Lossy, since a process can name itself with any bytes, and one bad name mustn't lose the whole file.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: buffer[..<count], as: UTF8.self)
    }

    /// Opens a file to read, with the user who owns it: a process's files are owned by the user it runs as.
    func openFile(_ path: String) -> (descriptor: Int32, ownerID: UInt32)? {
        // Not O_CLOEXEC, which musl follows with an fcntl call, one more system call for each of the
        // hundreds of files read a sample. Scout never starts a program that could inherit them.
        let descriptor = open(root + path, O_RDONLY)
        guard descriptor >= 0 else { return nil }
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            Self.close(descriptor)
            return nil
        }
        return (descriptor, UInt32(status.st_uid))
    }

    static func close(_ descriptor: Int32) {
        #if canImport(Darwin)
        _ = Darwin.close(descriptor)
        #elseif canImport(Glibc)
        _ = Glibc.close(descriptor)
        #else
        _ = Musl.close(descriptor)
        #endif
    }

    /// Reads an open file from its start into `buffer`, growing it when the file doesn't fit, and
    /// returns how many bytes it holds. The kernel makes a `/proc` file's text afresh when it's read
    /// from the start, so a file kept open gives current figures each time.
    ///
    /// - Parameter inOneRead: the kernel writes the whole file in one read when there's room, as it
    ///   does for a process's `stat` and `statm`, so a read that leaves room is taken as the end
    ///   rather than reading again to find it.
    static func readFromStart(_ descriptor: Int32, into buffer: inout [UInt8], inOneRead: Bool = false) -> Int? {
        // Files in /proc report a size of zero, so they're read until the end rather than by their size.
        var byteCount = 0
        while true {
            if byteCount == buffer.count {
                buffer.append(contentsOf: repeatElement(0, count: max(buffer.count, 4096)))
            }
            let count = buffer.withUnsafeMutableBytes { bytes in
                let rest = UnsafeMutableRawBufferPointer(rebasing: bytes[byteCount...])
                return pread(descriptor, rest.baseAddress, rest.count, off_t(byteCount))
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { return nil }
            if count == 0 { break }
            byteCount += count
            if inOneRead, byteCount < buffer.count { break }
        }
        return byteCount
    }

    /// The names in a folder, without `.` and `..`, or nil when it can't be read.
    func entries(in path: String) -> [String]? {
        guard let folder = opendir(root + path) else { return nil }
        defer { closedir(folder) }
        var names: [String] = []
        while let entry = readdir(folder) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }
            if name != ".", name != ".." { names.append(name) }
        }
        return names
    }

    /// Where a symbolic link points, as written in the link, or nil when it isn't one.
    func linkTarget(at path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let count = readlink(root + path, &buffer, buffer.count)
        guard count >= 0 else { return nil }
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: buffer[..<count].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// When the file last changed, in nanoseconds since 1970.
    func modificationTime(at path: String) -> Int64? {
        var status = stat()
        guard stat(root + path, &status) == 0 else { return nil }
        #if canImport(Darwin)
        let time = status.st_mtimespec
        #else
        let time = status.st_mtim
        #endif
        return Int64(time.tv_sec) * 1_000_000_000 + Int64(time.tv_nsec)
    }
}
