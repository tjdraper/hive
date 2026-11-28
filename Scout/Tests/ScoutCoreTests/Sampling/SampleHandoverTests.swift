import Foundation
@testable import ScoutCore
import ScoutProtocol
import Testing

struct SampleHandoverTests {
    /// A pipe's ends: what's written to the second is read from the first.
    private func pipeEnds() throws -> (read: Int32, write: Int32) {
        var descriptors: [Int32] = [-1, -1]
        try #require(pipe(&descriptors) == 0)
        return (descriptors[0], descriptors[1])
    }

    @Test("Samples handed down a pipe arrive whole and in order, and the stream ends when the hand-over stops")
    func handsOver() async throws {
        // Arrange
        let ends = try pipeEnds()
        let samples = try await SampleHandover.samples(from: ends.read, on: .shared)
        let handover = SampleHandover(pid: getpid(), input: ends.write)
        let sent = TestSamples.run(count: 3)

        // Act
        for sample in sent {
            try handover.hand(sample)
        }
        close(ends.write)
        var received: [MetricsSample] = []
        let ending = await #expect(throws: SampleHandoverError.ended) {
            for try await sample in samples {
                received.append(sample)
            }
        }

        // Assert
        #expect(ending != nil)
        #expect(received == sent)
    }

    @Test("A line that isn't a sample ends the stream, rather than being skipped")
    func refusesWhatIsNotASample() async throws {
        // Arrange
        let ends = try pipeEnds()
        let samples = try await SampleHandover.samples(from: ends.read, on: .shared)

        // Act
        let line = Array("{\"takenAt\":1}\n".utf8)
        #expect(write(ends.write, line, line.count) == line.count)
        defer { close(ends.write) }

        // Assert
        await #expect(throws: SampleHandoverError.notASample) {
            for try await _ in samples {
                continue
            }
        }
    }
}
