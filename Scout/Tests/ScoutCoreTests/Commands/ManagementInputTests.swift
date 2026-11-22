import Foundation
@testable import hive_scout
import ScoutProtocol
import Testing

struct ManagementInputTests {
    private let server: TemporaryServer

    init() throws {
        server = try TemporaryServer()
    }

    /// What `manage` reads, given `bytes` as its standard input.
    private func read(_ bytes: [UInt8]) throws -> ManagementInput? {
        let file = server.root.appending(path: "input")
        try Data(bytes).write(to: file)
        let descriptor = open(file.path(percentEncoded: false), O_RDONLY)
        defer { close(descriptor) }
        return ManagementInput.read(from: descriptor)
    }

    private static func line(_ request: ManagementRequest) throws -> [UInt8] {
        try Array(JSONEncoder().encode(request)) + [UInt8(ascii: "\n")]
    }

    @Test("An update's binary is exactly the bytes after the request line that it names")
    func update() throws {
        let binary = (0..<200_000).map { UInt8($0 % 251) }
        let request = ManagementRequest.update(statement: "statement", binaryLength: binary.count)

        #expect(try read(Self.line(request) + binary) == ManagementInput(request: request, binary: binary))
        #expect(try read(Self.line(request) + binary.dropLast()) == nil)
        #expect(try read(Self.line(request) + binary + [0]) == nil)
        #expect(try read(Self.line(.update(statement: "statement", binaryLength: 0))) == nil)
    }

    @Test("Other requests are one line and nothing after it, and anything else is refused")
    func otherRequests() throws {
        #expect(try read(Self.line(.status)) == ManagementInput(request: .status, binary: []))
        #expect(try read(Self.line(.install(code: "scout1:AQID"))) == ManagementInput(request: .install(code: "scout1:AQID"), binary: []))
        #expect(try read(Self.line(.uninstall) + [UInt8(ascii: "x")]) == nil)
        #expect(try read(Array(#"{"request":"status"}"#.utf8)) == nil)
        #expect(try read(Array("status\n".utf8)) == nil)
        #expect(try read(Array(#"{"request":"reboot"}"#.utf8) + [UInt8(ascii: "\n")]) == nil)
        #expect(try read([]) == nil)
    }
}
