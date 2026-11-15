import NIOCore
import ScoutCore
import Testing

struct ScoutEventLoopTests {
    @Test("Cancelling a wait ends it at once, so Scout can stop while waiting for the next mark")
    func cancelledWait() async {
        // Arrange
        let anHourAway = SampleSchedule.now() + 3_600 * 1_000_000_000
        let wait = Task { try await ScoutEventLoop.shared.sleep(untilWallClock: anHourAway) }

        // Act
        wait.cancel()

        // Assert
        await #expect(throws: (any Error).self) { try await wait.value }
    }

    @Test("A wait for a moment already past returns at once")
    func pastMoment() async throws {
        try await ScoutEventLoop.shared.sleep(untilWallClock: 0)
    }

    @Test("Work given to the loop runs on it, and so does what it awaits")
    func runsOnLoop() async throws {
        // Act
        let onLoop = try await ScoutEventLoop.shared.run {
            try await ScoutEventLoop.shared.sleep(untilWallClock: 0)
            return ScoutEventLoop.shared.loop.inEventLoop
        }

        // Assert
        #expect(onLoop)
    }
}
