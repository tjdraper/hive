import NIOCore
import NIOPosix

/// Scout's one thread: a SwiftNIO event loop that runs its connections, its tasks and its timers,
/// with a second thread kept for calls that block, such as looking up Hive's address.
///
/// Swift's default executor on Linux is libdispatch, which starts and stops worker threads as work
/// comes and goes. That costs CPU on every sample, and under the service's `Nice=10` each new thread
/// logs a failure to set its priority, writing to the journal. Run work with ``run(_:)``, wait with
/// ``sleep(untilWallClock:)``, never `Task.sleep`, whose timer is libdispatch's, and make blocking
/// calls with ``runBlocking(_:)``. NIO's own resolver is never used, since it hands lookups to libdispatch.
public final class ScoutEventLoop: TaskExecutor {
    public static let shared = ScoutEventLoop()

    public let loop: any EventLoop
    private let blockingCalls: NIOThreadPool

    private init() {
        loop = MultiThreadedEventLoopGroup(numberOfThreads: 1).next()
        blockingCalls = NIOThreadPool(numberOfThreads: 1)
        blockingCalls.start()
    }

    public func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        loop.execute { job.runSynchronously(on: self.asUnownedTaskExecutor()) }
    }

    /// Runs `operation` on the event loop, along with every task it starts.
    public func run<Result: Sendable>(_ operation: @escaping @Sendable () async throws -> Result) async throws -> Result {
        try await Task(executorPreference: self, operation: operation).value
    }

    /// Runs a call that blocks without holding up the event loop.
    func runBlocking<Result: Sendable>(_ call: @escaping @Sendable () throws -> Result) async throws -> Result {
        try await blockingCalls.runIfActive(call)
    }

    /// Waits until the wall clock reaches `nanoseconds` since 1970. A clock set back while waiting
    /// makes the wait longer, but the next mark is worked out afresh after it. Cancelling the task ends
    /// the wait with an error.
    public func sleep(untilWallClock nanoseconds: Int64) async throws {
        let delay = max(0, nanoseconds - SampleSchedule.now())
        let wake = loop.scheduleTask(in: .nanoseconds(delay)) { () }
        try await withTaskCancellationHandler {
            try await wake.futureResult.get()
        } onCancel: {
            wake.cancel()
        }
    }
}
