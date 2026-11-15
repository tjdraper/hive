#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ScoutCore
import ScoutProtocol

/// Prints a sample on every 10-second mark and, given a Hive, holds a pinned connection to it open,
/// reconnecting after a failure on the next mark.
struct WatchLoop {
    let target: ScoutCommand.HiveTarget?

    func run() async throws {
        let (marks, markInput) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        async let sampling: Void = takeSamples(signalling: markInput)
        if let target {
            try await holdConnection(to: target, marks: marks)
        }
        try await sampling
    }

    private func takeSamples(signalling marks: AsyncStream<Void>.Continuation) async throws {
        var sampler = Sampler()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        while true {
            let mark = SampleSchedule.nextMark(after: SampleSchedule.now())
            try await ScoutEventLoop.shared.sleep(untilWallClock: mark)
            let sample = sampler.sample(takenAt: mark / 1_000_000_000)
            Console.print(try encoder.encode(sample))
            marks.yield()
        }
    }

    private func holdConnection(to target: ScoutCommand.HiveTarget, marks: AsyncStream<Void>) async throws {
        var marks = marks.makeAsyncIterator()
        while true {
            do {
                try await PinnedHiveConnection.withConnection(to: target.address, pin: target.pin, on: .shared) { connection in
                    try await connection.checkHealth()
                    Console.log("Connected to Hive")
                    while await marks.next(isolation: #isolation) != nil {
                        try await connection.checkHealth()
                    }
                }
                return
            } catch HiveConnectionError.keyNotPinned {
                Console.log("Refused Hive: its key doesn't match the pin")
                throw HiveConnectionError.keyNotPinned
            } catch {
                Console.log("Couldn't reach Hive, trying again at the next sample: \(error)")
                _ = await marks.next(isolation: #isolation)
            }
        }
    }
}
