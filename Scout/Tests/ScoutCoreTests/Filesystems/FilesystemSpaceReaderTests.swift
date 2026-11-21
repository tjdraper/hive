#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import NIOCore
@testable import ScoutCore
import ScoutProtocol
import Synchronization
import Testing

struct FilesystemSpaceReaderTests {
    /// A filesystem that blocks `statvfs` until it's let go, as one on a failing disk does.
    private final class StuckFilesystem: Sendable {
        private let released = Mutex(false)
        private let calls = Mutex(0)

        var callCount: Int {
            calls.withLock { $0 }
        }

        func release() {
            released.withLock { $0 = true }
        }

        func measure() -> FilesystemSpace? {
            calls.withLock { $0 += 1 }
            while !released.withLock({ $0 }) {
                usleep(1000)
            }
            return FilesystemSpaceReaderTests.space
        }
    }

    private static let space = FilesystemSpace(sizeBytes: 100, usedBytes: 40, availableBytes: 50, inodes: nil)

    @Test("A filesystem that hangs is skipped, the others still answer, and it's read again once it returns")
    func hangingFilesystem() async throws {
        // Arrange
        let stuck = StuckFilesystem()
        let reader = FilesystemSpaceReader(timeout: .milliseconds(100)) { mountPoint in
            mountPoint == "/stuck" ? stuck.measure() : Self.space
        }

        // Act, Assert: the stuck one times out, and is skipped while its call is still waiting.
        #expect(await reader.space(of: "/stuck", on: .shared) == nil)
        #expect(await reader.space(of: "/", on: .shared) == Self.space)
        #expect(await reader.space(of: "/stuck", on: .shared) == nil)
        #expect(stuck.callCount == 1)

        // Once its call returns, it's read again.
        stuck.release()
        var space: FilesystemSpace?
        for _ in 0..<100 where space == nil {
            try await Task.sleep(for: .milliseconds(10))
            space = await reader.space(of: "/stuck", on: .shared)
        }
        #expect(space == Self.space)
        #expect(await reader.space(of: "/", on: .shared) == Self.space)
    }
}
