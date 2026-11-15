#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// Scout's output. Standard error goes to the system journal when Scout runs as a service.
enum Console {
    /// Writes a line of UTF-8, such as encoded JSON, to standard output.
    static func print(_ line: some Sequence<UInt8>) {
        write(STDOUT_FILENO, Array(line) + [UInt8(ascii: "\n")])
    }

    static func log(_ line: String) {
        write(STDERR_FILENO, Array((line + "\n").utf8))
    }

    private static func write(_ descriptor: Int32, _ line: [UInt8]) {
        var bytes = line[...]
        while !bytes.isEmpty {
            let written = bytes.withUnsafeBytes { buffer in
                #if canImport(Darwin)
                Darwin.write(descriptor, buffer.baseAddress, buffer.count)
                #elseif canImport(Glibc)
                Glibc.write(descriptor, buffer.baseAddress, buffer.count)
                #else
                Musl.write(descriptor, buffer.baseAddress, buffer.count)
                #endif
            }
            if written < 0, errno == EINTR { continue }
            guard written > 0 else { return }
            bytes = bytes.dropFirst(written)
        }
    }
}
