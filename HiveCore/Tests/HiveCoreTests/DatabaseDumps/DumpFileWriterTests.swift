import Darwin
import Foundation
@testable import HiveCore
import os
import Testing

struct DumpFileWriterTests {
    /// Enough to fill zlib's output buffer several times over, in pieces the size a pipe hands over.
    private static let largeDump: Data = {
        var generator = SystemRandomNumberGenerator()
        let lines = (0 ..< 40000).map { "INSERT INTO entries VALUES (\($0), '\(generator.next() as UInt64)');\n" }
        return Data(lines.joined().utf8)
    }()

    private func write(_ dump: Data, compressed: Bool, to url: URL) throws -> DumpFileSummary {
        let writer = try DumpFileWriter(creating: url, compressed: compressed)
        var offset = 0
        while offset < dump.count {
            let end = min(offset + 16384, dump.count)
            try writer.write(dump[offset ..< end])
            offset = end
        }
        return try writer.finish()
    }

    @Test("A compressed dump is a gzip file of exactly what was written, and its summary counts both sizes")
    func compressed() throws {
        // Arrange
        let temporary = try TemporaryDirectory()
        let url = temporary.url.appending(path: "site.sql.gz")

        // Act
        let summary = try write(Self.largeDump, compressed: true, to: url)

        // Assert
        #expect(try gunzip(url) == Self.largeDump)
        #expect(summary.bytesDumped == Int64(Self.largeDump.count))
        #expect(summary.bytesStored == Int64(try Data(contentsOf: url).count))
        #expect(summary.bytesStored < summary.bytesDumped)
        #expect(summary.beginning == Self.largeDump.prefix(DumpFileSummary.keptBytes))
        #expect(summary.ending == Self.largeDump.suffix(DumpFileSummary.keptBytes))
    }

    @Test("An uncompressed dump is stored as it came")
    func uncompressed() throws {
        // Arrange
        let temporary = try TemporaryDirectory()
        let url = temporary.url.appending(path: "site.dump")

        // Act
        let summary = try write(Self.largeDump, compressed: false, to: url)

        // Assert
        #expect(try Data(contentsOf: url) == Self.largeDump)
        #expect(summary.bytesStored == summary.bytesDumped)
    }

    @Test("A dump file can be read only by Hive's user")
    func ownerOnly() throws {
        // Arrange
        let temporary = try TemporaryDirectory()
        let url = temporary.url.appending(path: "site.dump")

        // Act
        _ = try write(RecordedDumpOutput.postgresDump, compressed: false, to: url)

        // Assert
        #expect(try permissions(of: url.fileSystemPath) == 0o600)
    }

    @Test("Nothing already there, or a link there, is written through")
    func refusesExisting() throws {
        // Arrange
        let temporary = try TemporaryDirectory()
        let existing = temporary.url.appending(path: "existing.dump")
        try Data("keep".utf8).write(to: existing)
        let link = temporary.url.appending(path: "link.dump")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: temporary.url.appending(path: "elsewhere"))

        // Act & Assert
        #expect(throws: DumpFileError.couldNotCreate(errno: EEXIST)) { try DumpFileWriter(creating: existing, compressed: false) }
        #expect(throws: DumpFileError.couldNotCreate(errno: EEXIST)) { try DumpFileWriter(creating: link, compressed: true) }
        #expect(try Data(contentsOf: existing) == Data("keep".utf8))
        #expect(!FileManager.default.fileExists(atPath: temporary.url.appending(path: "elsewhere").fileSystemPath))
    }
}

struct ChildProcessOutputHandlerTests {
    private struct Refused: Error {}

    @Test("A handler gets all of standard output in order, and none of it is collected")
    func handlerGetsEverything() async throws {
        // Arrange
        let received = ReceivedOutput()
        var process = ChildProcess(
            executableURL: URL(filePath: "/bin/sh"),
            arguments: ["-c", "head -c 300000 /dev/zero | tr '\\0' x; echo done >&2"],
            environment: SSHTools.environment()
        )
        process.standardOutputHandler = { received.append($0) }

        // Act
        let result = try await process.run()

        // Assert
        #expect(result.status == 0)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError == Data("done\n".utf8))
        #expect(received.data == Data(repeating: UInt8(ascii: "x"), count: 300_000))
    }

    @Test("A handler that throws stops the process, and running it throws that error")
    func handlerFailureStops() async throws {
        // Arrange
        var process = ChildProcess(executableURL: URL(filePath: "/usr/bin/yes"), arguments: [], environment: SSHTools.environment())
        process.standardOutputHandler = { _ in throw Refused() }

        // Act & Assert
        await #expect(throws: Refused.self) { try await process.run() }
    }
}

/// Collects data from a handler called on another queue.
final class ReceivedOutput: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Data())

    var data: Data {
        lock.withLock { $0 }
    }

    func append(_ data: Data) {
        lock.withLock { $0.append(data) }
    }
}
