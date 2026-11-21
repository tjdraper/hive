import Foundation
@testable import ScoutCore
import ScoutProtocol
import Synchronization
import Testing

struct SendingCoordinatorTests {
    private static let now = TestSamples.start + 100_000

    private let hive = FakeHive()
    private let folder: TemporaryServer
    private let logs = Recorded<String>()
    private let waits = Recorded<Duration>()
    private let queue = MetricsQueue()

    init() throws {
        folder = try TemporaryServer()
    }

    private func enroll(hosts: [String] = ["hive"]) async throws -> SavedEnrollment {
        let store = EnrollmentStore(directory: folder.root.path(percentEncoded: false))
        return try await EnrollmentWorkflow(connector: hive, store: store).enroll(with: hive.code(hosts: hosts))
    }

    /// `onWait` is given how many waits there have been, and stops the coordinator by default.
    private func coordinator(
        onWait: @escaping @Sendable (Int) throws -> Void = { _ in throw CancellationError() }
    ) -> SendingCoordinator {
        SendingCoordinator(
            connector: hive,
            metrics: queue,
            log: { [logs] in logs.append($0) },
            now: { Self.now },
            wait: { [waits] duration in
                waits.append(duration)
                try onWait(waits.all.count)
            }
        )
    }

    /// Runs until everything waiting is sent, with no more samples coming.
    private func sendWaiting(_ coordinator: SendingCoordinator, as enrollment: SavedEnrollment) async throws {
        let (marks, input) = AsyncStream.makeStream(of: Void.self)
        input.finish()
        try await coordinator.run(enrollment: enrollment, marks: marks)
    }

    private func logged(_ text: String) -> Int {
        logs.all.filter { $0.contains(text) }.count
    }

    @Test("While Hive is unreachable Scout waits longer between tries, up to a minute, then sends the newest first, the rest oldest first")
    func backsOffThenCatchesUp() async throws {
        // Arrange
        let enrollment = try await enroll()
        let samples = TestSamples.run(count: 5)
        for sample in samples { queue.add(sample) }
        hive.set { $0.reach = ["hive": .unreachable] }
        let coordinator = coordinator { [hive] count in
            if count == 5 { hive.set { $0.reach = [:] } }
        }

        // Act
        try await sendWaiting(coordinator, as: enrollment)

        // Assert
        #expect(waits.all == [.seconds(10), .seconds(20), .seconds(40), .seconds(60), .seconds(60)])
        #expect(hive.reports.map { $0.samples.map(\.takenAt) } == [[samples[4].takenAt], samples[0 ..< 4].map(\.takenAt)])
        #expect(hive.reports.allSatisfy { $0.protocolVersion == ScoutProtocolVersion.current && $0.sentAt == Self.now })
        #expect(logged("Couldn't reach Hive") == 1)
        #expect(logged("Sending to Hive") == 1)
        #expect(coordinator.status.state == .sending)
        #expect(coordinator.status.lastDeliveredAt == Self.now)
        #expect(queue.held.samples == 0)
    }

    @Test("When Hive has forgotten the session, as after it restarted, Scout signs in again and sends each sample once")
    func signsInAgain() async throws {
        // Arrange
        let enrollment = try await enroll()
        let samples = TestSamples.run(count: 2)
        for sample in samples { queue.add(sample) }
        hive.set { state in
            state.onMetrics = { [hive] in hive.set { $0.restarts += 1; $0.onMetrics = nil } }
        }

        // Act
        try await sendWaiting(coordinator(), as: enrollment)

        // Assert: one sign-in while enrolling, one to start sending, and one after the restart.
        #expect(hive.reports.map { $0.samples.map(\.takenAt) } == [[samples[1].takenAt], [samples[0].takenAt]])
        #expect(hive.signIns == 3)
        #expect(waits.all.isEmpty)
    }

    @Test("Samples Hive refuses are dropped, not sent again, and the reason is logged once")
    func refusedSamples() async throws {
        // Arrange
        let enrollment = try await enroll()
        for sample in TestSamples.run(count: 2) { queue.add(sample) }
        hive.set { $0.metricsStatuses = [422, 422]; $0.metricsRefusal = .clockAhead }

        // Act
        try await sendWaiting(coordinator(), as: enrollment)

        // Assert
        #expect(hive.reports.count == 2)
        #expect(queue.held.samples == 0)
        #expect(logged("clock-ahead") == 1)
    }

    @Test(
        "A Scout Hive no longer recognizes or accepts is logged once, keeps its samples, and tries again hourly",
        arguments: [UInt(401), 409]
    )
    func refusedForGood(signInStatus: UInt) async throws {
        // Arrange
        let enrollment = try await enroll()
        for sample in TestSamples.run(count: 3) { queue.add(sample) }
        hive.set { $0.signInStatus = signInStatus }
        let coordinator = coordinator { count in
            if count == 2 { throw CancellationError() }
        }

        // Act
        await #expect(throws: CancellationError.self) { try await sendWaiting(coordinator, as: enrollment) }

        // Assert
        #expect(waits.all == [.seconds(3_600), .seconds(3_600)])
        #expect(logged("Refused by Hive") == 1)
        #expect(coordinator.status.state == .refused)
        #expect(queue.held.samples == 3)
        #expect(hive.reports.isEmpty)
    }

    @Test("A run ended for a reload and started again with a new enrollment connects at once and keeps what's held")
    func reload() async throws {
        // Arrange: Hive has removed this Scout, so the first run waits an hour.
        let removed = try await enroll()
        for sample in TestSamples.run(count: 3) { queue.add(sample) }
        hive.set { $0.signInStatus = 401 }
        let coordinator = coordinator()
        await #expect(throws: CancellationError.self) { try await sendWaiting(coordinator, as: removed) }
        hive.set { $0.signInStatus = nil }
        let enrolledAgain = try await enroll()

        // Act
        try await sendWaiting(coordinator, as: enrolledAgain)

        // Assert
        #expect(waits.all == [.seconds(3_600)])
        #expect(hive.reports.flatMap(\.samples).count == 3)
        #expect(coordinator.status.state == .sending)
        #expect(queue.held.samples == 0)
    }

    @Test("Another key at every address is refused hourly, but beside an address that can't be reached it counts as unreachable")
    func otherKey() async throws {
        // Arrange
        let enrollment = try await enroll(hosts: ["first", "second"])
        queue.add(TestSamples.sample(at: TestSamples.start))

        // Act, Assert
        hive.set { $0.reach = ["first": .otherKey, "second": .otherKey] }
        let everyAddress = coordinator()
        await #expect(throws: CancellationError.self) { try await sendWaiting(everyAddress, as: enrollment) }
        #expect(waits.all == [.seconds(3_600)])
        #expect(everyAddress.status.state == .refused)

        hive.set { $0.reach = ["first": .otherKey, "second": .unreachable] }
        let oneAddress = coordinator()
        await #expect(throws: CancellationError.self) { try await sendWaiting(oneAddress, as: enrollment) }
        #expect(waits.all == [.seconds(3_600), .seconds(10)])
        #expect(oneAddress.status.state == .unreachable)
        #expect(hive.reports.isEmpty)
    }
}

final class Recorded<Value: Sendable>: Sendable {
    private let values = Mutex<[Value]>([])

    var all: [Value] {
        values.withLock { $0 }
    }

    func append(_ value: Value) {
        values.withLock { $0.append(value) }
    }
}
