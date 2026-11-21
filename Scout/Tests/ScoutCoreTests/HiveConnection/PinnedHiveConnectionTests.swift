import Foundation
import NIOCore
@testable import ScoutCore
import Testing

struct PinnedHiveConnectionTests {
    @Test("A Hive that accepts the connection and never answers times out, rather than leaving Scout waiting")
    func neverAnswers() async throws {
        // Arrange: a connected socket whose other end is never read or answered, so no port is opened.
        var ends: [Int32] = [0, 0]
        #if canImport(Glibc)
        let streamType = Int32(SOCK_STREAM.rawValue)
        #else
        let streamType = SOCK_STREAM
        #endif
        try #require(socketpair(AF_UNIX, streamType, 0, &ends) == 0)
        let (scoutEnd, hiveEnd) = (ends[0], ends[1])
        defer { close(hiveEnd) }
        let pin = HiveKeyPin(sha256: Array(repeating: 0xAB, count: 32))
        let started = ContinuousClock.now

        // Act, Assert
        await #expect(throws: HiveConnectionError.timedOut) {
            try await PinnedHiveConnection.withConnection(
                connectedSocket: scoutEnd,
                pin: pin,
                on: .shared,
                requestTimeout: .milliseconds(200)
            ) { connection in
                try await connection.send("GET", "/health")
            }
        }
        #expect(ContinuousClock.now - started < .seconds(5))
    }
}
