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
        let descriptor = open(root + path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        // Files in /proc report a size of zero, so they're read until the end rather than by their size.
        var contents: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = chunk.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { return nil }
            if count == 0 { break }
            contents.append(contentsOf: chunk[0..<count])
        }
        // Lossy, since a process can name itself with any bytes, and one bad name mustn't lose the whole file.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: contents, as: UTF8.self)
    }
}
