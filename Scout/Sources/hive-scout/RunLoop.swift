import ScoutCore
import ScoutProtocol
import Synchronization

/// Takes a sample on every 10-second mark and sends it to the Hive this Scout enrolled with. Sampling
/// only adds to the queue, so a slow or stuck Hive can't delay or skip a sample.
struct RunLoop {
    let enrollment: SavedEnrollment
    let statusFile: SendingStatusFile

    func run() async throws {
        let queue = MetricsQueue()
        let coordinator = SendingCoordinator(
            enrollment: enrollment,
            connector: PinnedHiveConnector(),
            metrics: queue,
            log: { Console.log($0) },
            now: { SampleSchedule.now() / 1_000_000_000 },
            wait: { try await ScoutEventLoop.shared.sleep(for: $0) }
        )
        let (marks, markInput) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        Console.log("Started, sending to Hive for server \(enrollment.serverID)")
        async let sampling: Void = takeSamples(into: queue, signalling: markInput, coordinator: coordinator)
        try await coordinator.run(marks: marks)
        try await sampling
    }

    private func takeSamples(
        into queue: MetricsQueue,
        signalling marks: AsyncStream<Void>.Continuation,
        coordinator: SendingCoordinator
    ) async throws {
        var sampler = Sampler()
        var statusFailed = false
        while true {
            let mark = SampleSchedule.nextMark(after: SampleSchedule.now())
            try await ScoutEventLoop.shared.sleep(untilWallClock: mark)
            queue.add(await sampler.sample(takenAt: mark / 1_000_000_000))
            marks.yield()
            do {
                try statusFile.save(coordinator.status)
                statusFailed = false
            } catch {
                if !statusFailed { Console.log("Couldn't write the status for hive-scout status: \(error)") }
                statusFailed = true
            }
        }
    }
}
