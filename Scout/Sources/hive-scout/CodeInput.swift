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
enum CodeInput: Equatable {
    case code(EnrollmentCode)
    /// Nothing but a blank line or the end of the input, which `install` takes as keeping the
    /// enrollment the server has.
    case nothing
    case notACode

    /// Far longer than a code with the most addresses.
    static let longest = 4096

    static func read(prompt: String) -> Self {
        if isatty(STDIN_FILENO) == 1 { Console.log(prompt) }
        var text: [UInt8] = []
        var byte: UInt8 = 0
        while text.count < longest {
            let count = readByte(&byte)
            if count < 0, errno == EINTR { continue }
            guard count == 1 else { break }
            text.append(byte)
            guard byte == UInt8(ascii: "\n") else { continue }
            if isBlank(text) { return .nothing }
            if let code = parse(text) { return .code(code) }
        }
        if isBlank(text) { return .nothing }
        return parse(text).map(Self.code) ?? .notACode
    }

    private static func isBlank(_ text: [UInt8]) -> Bool {
        text.allSatisfy { [UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\r"), UInt8(ascii: "\n")].contains($0) }
    }

    private static func parse(_ text: [UInt8]) -> EnrollmentCode? {
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
