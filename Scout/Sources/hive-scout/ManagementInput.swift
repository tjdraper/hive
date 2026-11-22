#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import ScoutProtocol

/// A `ManagementRequest` read from standard input, with an update's binary, held in memory.
struct ManagementInput: Equatable {
    let request: ManagementRequest
    let binary: [UInt8]

    /// Nil for anything but one request line, followed by exactly the binary it names for an update,
    /// and nothing at all for any other request.
    static func read(from descriptor: Int32 = STDIN_FILENO) -> Self? {
        guard let bytes = readAll(from: descriptor, limit: ManagementRequest.longestLine + ManagementRequest.largestBinary),
              let newline = bytes.firstIndex(of: UInt8(ascii: "\n")), newline < ManagementRequest.longestLine,
              let request = try? JSONDecoder().decode(ManagementRequest.self, from: Data(bytes[..<newline]))
        else { return nil }
        let rest = Array(bytes[(newline + 1)...])
        switch request.request {
        case .update:
            guard let length = request.binaryLength, (1...ManagementRequest.largestBinary).contains(length),
                  rest.count == length
            else { return nil }
        case .status, .install, .uninstall:
            guard rest.isEmpty else { return nil }
        }
        return Self(request: request, binary: rest)
    }

    /// Everything until the end of the input, or nil past `limit` bytes.
    private static func readAll(from descriptor: Int32, limit: Int) -> [UInt8]? {
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        while bytes.count <= limit {
            let count = buffer.withUnsafeMutableBytes { readDescriptor(descriptor, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { return nil }
            guard count > 0 else { return bytes }
            bytes += buffer[..<count]
        }
        return nil
    }

    private static func readDescriptor(_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.read(descriptor, buffer, count)
        #elseif canImport(Glibc)
        Glibc.read(descriptor, buffer, count)
        #else
        Musl.read(descriptor, buffer, count)
        #endif
    }
}
