#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
#if canImport(os)
import os
#endif

/// Scout's output. Standard error goes to the system journal when Scout runs as a service on Linux. A
/// Mac's launchd keeps no output, so there each line goes to the system log too.
enum Console {
    #if canImport(os)
    private static let systemLog = Logger(subsystem: "com.buzzingpixel.HiveScout", category: "Scout")
    #endif

    /// Writes a line of UTF-8, such as encoded JSON, to standard output.
    static func print(_ line: some Sequence<UInt8>) {
        write(STDOUT_FILENO, Array(line) + [UInt8(ascii: "\n")])
    }

    /// Never given Scout's key or an enrollment code, so it's all public.
    static func log(_ line: String) {
        #if canImport(os)
        systemLog.log("\(line, privacy: .public)")
        #endif
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
