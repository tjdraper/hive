#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import ScoutProtocol

/// Reads an enrollment code from standard input, where neither `ps` nor the journal sees it. A
/// terminal may wrap a pasted code over several lines, so lines are read until they make a whole code.
enum CodeInput {
    /// Far longer than a code with the most addresses.
    static let longest = 4096

    static func read() -> EnrollmentCode? {
        if isatty(STDIN_FILENO) == 1 { Console.log("Paste the enrollment code from Beekeeper, then press Return:") }
        var text: [UInt8] = []
        var byte: UInt8 = 0
        while text.count < longest {
            let count = readByte(&byte)
            if count < 0, errno == EINTR { continue }
            guard count == 1 else { break }
            text.append(byte)
            if byte == UInt8(ascii: "\n"), let code = code(in: text) { return code }
        }
        return code(in: text)
    }

    private static func code(in text: [UInt8]) -> EnrollmentCode? {
        String(validating: text, as: UTF8.self).flatMap(EnrollmentCode.init(text:))
    }

    private static func readByte(_ byte: inout UInt8) -> Int {
        withUnsafeMutableBytes(of: &byte) { buffer in
            #if canImport(Darwin)
            Darwin.read(STDIN_FILENO, buffer.baseAddress, 1)
            #elseif canImport(Glibc)
            Glibc.read(STDIN_FILENO, buffer.baseAddress, 1)
            #else
            Musl.read(STDIN_FILENO, buffer.baseAddress, 1)
            #endif
        }
    }
}
