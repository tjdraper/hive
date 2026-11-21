#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import NIOCore
import NIOPosix
import ScoutProtocol
import Synchronization

/// Asks filesystems for their space on a thread of its own, giving up on one that doesn't answer in
/// time. A filesystem whose disk is failing can block `statvfs` for minutes, and nothing can interrupt
/// it, so that thread is left waiting: the filesystem is skipped until its call returns, and a spare
/// thread takes over the others. A thread whose call has returned becomes the next spare, so no more
/// threads are kept than calls stuck at once.
final class FilesystemSpaceReader: Sendable {
    typealias Measure = @Sendable (_ mountPoint: String) -> FilesystemSpace?

    private struct Threads {
        var current: NIOThreadPool
        var spares: [NIOThreadPool] = []
        var hanging: Set<String> = []
    }

    /// Settles a call once, by its answer or by the timeout, whichever comes first.
    private final class Outcome: Sendable {
        private let settled = Mutex(false)

        func settle() -> Bool {
            settled.withLock { settled in
                defer { settled = true }
                return !settled
            }
        }
    }

    private let measure: Measure
    private let timeout: TimeAmount
    private let threads: Mutex<Threads>

    init(timeout: TimeAmount = .seconds(2), measure: @escaping Measure) {
        self.measure = measure
        self.timeout = timeout
        threads = Mutex(Threads(current: Self.startThread()))
    }

    convenience init(files: SystemFiles) {
        self.init { mountPoint in Self.statvfsSpace(at: files.root + mountPoint) }
    }

    /// The filesystem's space, or nil when it couldn't be read, didn't answer in time, or still hasn't
    /// answered an earlier call.
    func space(of mountPoint: String, on eventLoop: ScoutEventLoop) async -> FilesystemSpace? {
        let thread: NIOThreadPool? = threads.withLock { $0.hanging.contains(mountPoint) ? nil : $0.current }
        guard let thread else { return nil }
        let measure = measure
        return await withCheckedContinuation { continuation in
            let outcome = Outcome()
            let timer = eventLoop.loop.scheduleTask(in: timeout) {
                guard outcome.settle() else { return }
                self.threads.withLock { threads in
                    threads.hanging.insert(mountPoint)
                    threads.current = threads.spares.popLast() ?? Self.startThread()
                }
                continuation.resume(returning: nil)
            }
            thread.runIfActive(eventLoop: eventLoop.loop) { measure(mountPoint) }.whenComplete { result in
                timer.cancel()
                if outcome.settle() {
                    continuation.resume(returning: try? result.get())
                } else {
                    self.threads.withLock { threads in
                        threads.hanging.remove(mountPoint)
                        threads.spares.append(thread)
                    }
                }
            }
        }
    }

    private static func startThread() -> NIOThreadPool {
        let thread = NIOThreadPool(numberOfThreads: 1)
        thread.start()
        return thread
    }

    /// The same figures `df` shows. Filesystems without a fixed number of inodes report none.
    static func statvfsSpace(at path: String) -> FilesystemSpace? {
        var figures = statvfs()
        guard statvfs(path, &figures) == 0 else { return nil }
        let blockSize = UInt64(figures.f_frsize)
        let blocks = UInt64(figures.f_blocks)
        let freeBlocks = UInt64(figures.f_bfree)
        let inodes = UInt64(figures.f_files)
        let freeInodes = UInt64(figures.f_ffree)
        return FilesystemSpace(
            sizeBytes: blocks * blockSize,
            usedBytes: (blocks - min(freeBlocks, blocks)) * blockSize,
            availableBytes: UInt64(figures.f_bavail) * blockSize,
            inodes: inodes == 0 ? nil : InodeCounts(used: inodes - min(freeInodes, inodes), free: freeInodes)
        )
    }
}
