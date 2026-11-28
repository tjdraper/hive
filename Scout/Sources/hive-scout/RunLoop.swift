import ScoutCore
import ScoutProtocol
import Synchronization

/// Sends each sample, taken on every 10-second mark, to the Hive this Scout enrolled with. Sampling
/// only adds to the queue, so a slow or stuck Hive can't delay or skip a sample. SIGHUP reads the
/// enrollment again and connects at once, keeping what's held.
struct RunLoop {
    let enrollment: SavedEnrollment
    let store: EnrollmentStore
    let statusFile: SendingStatusFile
    /// Taken by this process, or handed to it by `run` as root on a Mac. Scout stops when they end.
    let samples: AsyncThrowingStream<MetricsSample, any Error>

    /// Takes a sample on every 10-second mark.
    static func samplesTakenHere() -> AsyncThrowingStream<MetricsSample, any Error> {
        let (samples, output) = AsyncThrowingStream.makeStream(of: MetricsSample.self, bufferingPolicy: .bufferingNewest(60))
        let sampling = Task(executorPreference: ScoutEventLoop.shared) {
            var sampler = ServerSampler()
            do {
                while true {
                    let mark = SampleSchedule.nextMark(after: SampleSchedule.now())
                    try await ScoutEventLoop.shared.sleep(untilWallClock: mark)
                    output.yield(await sampler.sample(takenAt: mark / 1_000_000_000))
                }
            } catch {
                output.finish(throwing: error)
            }
        }
        output.onTermination = { _ in sampling.cancel() }
        return samples
    }

    func run() async throws {
        let reloads = try await ReloadSignal.listen(on: .shared)
        let queue = MetricsQueue()
        let coordinator = SendingCoordinator(
            connector: PinnedHiveConnector(),
            metrics: queue,
            log: { Console.log($0) },
            now: { SampleSchedule.now() / 1_000_000_000 },
            wait: { try await ScoutEventLoop.shared.sleep(for: $0) }
        )
        let marks = Marks()
        Console.log("Started, sending to Hive for server \(enrollment.serverID)")
        // Either ending ends Scout, such as when the process handing it samples stops.
        try await withThrowingTaskGroup { group in
            group.addTask { try await keepSamples(into: queue, signalling: marks, coordinator: coordinator) }
            group.addTask { try await send(with: coordinator, marks: marks, reloads: reloads) }
            try await group.next()
        }
    }

    private func send(with coordinator: SendingCoordinator, marks: Marks, reloads: AsyncStream<Void>) async throws {
        var enrollment = enrollment
        var reloads = reloads.makeAsyncIterator()
        while true {
            let runMarks = marks.startRun()
            let sending = Task(executorPreference: ScoutEventLoop.shared) { [enrollment] in
                try await coordinator.run(enrollment: enrollment, marks: runMarks)
            }
            guard await reloads.next(isolation: #isolation) != nil else {
                if Task.isCancelled { sending.cancel() }
                return try await sending.value
            }
            sending.cancel()
            _ = try? await sending.value
            enrollment = reloaded() ?? enrollment
        }
    }

    /// The enrollment saved now, or nil when it can't be read, which keeps the one in use.
    private func reloaded() -> SavedEnrollment? {
        do {
            guard let saved = try store.load() else {
                Console.log("Reloading found no enrollment, so Scout keeps the one it has.")
                return nil
            }
            Console.log("Reloaded the enrollment, sending to Hive for server \(saved.serverID)")
            return saved
        } catch {
            Console.log("Couldn't read the enrollment again, so Scout keeps the one it has: \(error)")
            return nil
        }
    }

    private func keepSamples(
        into queue: MetricsQueue,
        signalling marks: Marks,
        coordinator: SendingCoordinator
    ) async throws {
        var statusFailed = false
        for try await sample in samples {
            queue.add(sample)
            marks.yield()
            do {
                try statusFile.save(coordinator.status)
                statusFailed = false
            } catch {
                if !statusFailed { Console.log("Couldn't write the status for hive-scout status: \(error)") }
                statusFailed = true
            }
        }
        throw SampleHandoverError.ended
    }

    /// Tells the coordinator a sample was taken. Each of its runs has marks of its own, since
    /// cancelling a task that waits on a stream ends the stream.
    private final class Marks: Sendable {
        private let input = Mutex<AsyncStream<Void>.Continuation?>(nil)

        func startRun() -> AsyncStream<Void> {
            let (marks, input) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
            self.input.withLock { $0 = input }
            return marks
        }

        func yield() {
            input.withLock { $0 }?.yield()
        }
    }
}
