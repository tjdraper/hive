import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Synchronization
import Testing

/// What a live updates response sent, once it ended.
private struct LiveAnswer {
    let status: HTTPResponse.Status
    /// Every line but heartbeats.
    let updates: [LiveUpdate]

    var events: [RunEvent] {
        updates.compactMap { update in
            guard case .event(let event) = update else { return nil }
            return event
        }
    }
}

/// What a live updates stream wrote, as it writes it.
private final class WrittenUpdates: Sendable {
    private let written = Mutex<[LiveUpdate]>([])

    var updates: [LiveUpdate] {
        written.withLock { $0 }
    }

    func append(_ update: LiveUpdate) {
        written.withLock { $0.append(update) }
    }

    /// Waits, for up to five seconds, until what's written so far passes `check`.
    func wait(until check: ([LiveUpdate]) -> Bool) async throws {
        for _ in 0 ..< 500 {
            if check(updates) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw RunWaitError.timedOut
    }
}

private extension APIFixture {
    /// Opens live updates with `token`, runs `meanwhile` once Hive is listening for events, and returns
    /// what was sent once the response ends, which `meanwhile` has to bring about.
    func liveUpdates(token: String, meanwhile: () async throws -> Void) async throws -> LiveAnswer {
        let headers = headers(token: token)
        async let answer = application.test(.router) { client in
            try await client.execute(uri: HiveEndpoint.liveUpdates, method: .get, headers: headers) { response in
                let lines = String(buffer: response.body).split(separator: "\n")
                let updates = try lines.map { try JSONDecoder().decode(LiveUpdate.self, from: Data($0.utf8)) }
                return LiveAnswer(
                    status: response.status,
                    updates: updates.filter { $0 != .heartbeat }
                )
            }
        }
        for _ in 0 ..< 500 where api.runs.events.listenerCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await meanwhile()
        return try await answer
    }

    /// Ends every session, as if they all ran out.
    func outliveSessions() {
        signIn.clock.advance(by: SessionStore.lifetime + 1)
    }
}

struct LiveUpdateTests {
    @Test("Live updates are refused without signing in, with an unknown token, and once the session has run out")
    func refusedWithoutSigningIn() async throws {
        // Arrange
        let fixture = try APIFixture()
        let expired = try fixture.token()
        fixture.outliveSessions()

        // Act
        let statuses = try await fixture.application.test(.router) { client in
            var statuses: [HTTPResponse.Status] = []
            for headers in [[:], fixture.headers(token: "made-up"), fixture.headers(token: expired)] as [HTTPFields] {
                statuses.append(try await client.execute(uri: HiveEndpoint.liveUpdates, method: .get, headers: headers) { $0.status })
            }
            return statuses
        }

        // Assert
        #expect(statuses == [.unauthorized, .unauthorized, .unauthorized])
    }

    @Test(
        "Live updates start with every job's status, then a run's events as it goes, with the job's status as it changes",
        .timeLimit(.minutes(1))
    )
    func runAsItGoes() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        let written = WrittenUpdates()
        let stream = LiveUpdateStream(events: fixture.runs.events, statuses: fixture.api.api.jobStatus, heartbeat: .seconds(3600)) { true }
        let following = Task { try await stream.run { written.append($0) } }
        try await written.wait { $0.count == 1 }

        // Act
        _ = try await fixture.runNow()
        await fixture.runs.waitUntilIdle()
        try await written.wait { updates in
            guard case .jobStatus(let status) = updates.last else { return false }
            return status.lastRun != nil
        }
        following.cancel()

        // Assert
        let updates = written.updates
        guard case .jobStatuses(let first) = updates.first else {
            Issue.record("The first line wasn't every job's status")
            return
        }
        #expect(first.map(\.jobID) == [fixture.job.id])
        #expect(first.first?.state == .idle)
        let events = updates.compactMap { update -> RunEvent? in
            guard case .event(let event) = update else { return nil }
            return event
        }
        #expect(events.map(Self.describe) == [
            "queued",
            "started",
            "checkingDirectories",
            "pulling(folder: \"site\")",
            "progress",
            "completing",
            "finished",
        ])
        guard case .jobStatus(let last) = updates.last, case .finished(let finished) = events.last else {
            Issue.record("The job's status didn't follow the finished run")
            return
        }
        #expect(last.state == .idle)
        #expect(last.lastRun == finished)
        #expect(finished.run.failure == nil)
        #expect(try await following.value == .hiveStopping)
    }

    @Test("Live updates end within a heartbeat once the session runs out", .timeLimit(.minutes(1)))
    func endsWithTheSession() async throws {
        // Arrange
        let fixture = try APIFixture(liveUpdateHeartbeat: .milliseconds(10))
        let token = try fixture.token()

        // Act
        let answer = try await fixture.liveUpdates(token: token) {
            try await Task.sleep(for: .milliseconds(50))
            fixture.outliveSessions()
        }

        // Assert
        #expect(answer.status == .ok)
        #expect(answer.updates == [.jobStatuses([])])
    }

    @Test("A quiet stream gets heartbeats", .timeLimit(.minutes(1)))
    func heartbeats() async throws {
        // Arrange
        let fixture = try APIFixture()
        let written = WrittenUpdates()
        let api = fixture.api
        let stream = LiveUpdateStream(events: api.runs.events, statuses: api.jobStatus, heartbeat: .milliseconds(10)) { true }

        // Act
        let following = Task { try await stream.run { written.append($0) } }
        try await written.wait { $0.count { $0 == .heartbeat } >= 2 }
        following.cancel()

        // Assert
        #expect(written.updates.first == .jobStatuses([]))
    }

    @Test("A revoked device's live updates end, and nothing more reaches it", .timeLimit(.minutes(1)))
    func endsWhenRevoked() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        let otherKey = P256.Signing.PrivateKey()
        let other = try fixture.api.signIn.devices.add(
            name: "Office iPad",
            publicKey: otherKey.publicKey.x963Representation,
            at: fixture.clock.now,
            auditedAs: .pairedOnHiveMac
        )
        let token = try fixture.api.token(for: other, key: otherKey)

        // Act
        let answer = try await fixture.api.liveUpdates(token: token) {
            _ = try fixture.api.api.revocation.revoke(other.id, by: fixture.api.signIn.device.id)
            _ = try await fixture.runNow()
            await fixture.runs.waitUntilIdle()
        }

        // Assert
        #expect(answer.updates.count == 1)
        #expect(answer.events.isEmpty)
    }

    @Test("Snapshots retention removes are told to listeners, as in the job log")
    func removalsAreTold() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try await fixture.setTiers(daily: 1, monthly: 1)
        let first = try await fixture.runDaysApart([1])
        let events = fixture.runs.events.listen()

        // Act
        try await fixture.runDaysApart([1])

        // Assert
        var removal: RemovalLogEntry?
        for await event in events {
            if case .removed(let entry) = event {
                removal = entry
                break
            }
        }
        #expect(removal?.removed.map(\.snapshotID) == first.map(\.id))
        #expect(try await fixture.removals() == [try #require(removal)])
    }

    private static func describe(_ event: RunEvent) -> String {
        switch event {
        case .queued: "queued"
        case .leftQueue: "left queue"
        case .started: "started"
        case .step(_, let step): "\(step)"
        case .progress: "progress"
        case .finished: "finished"
        case .removed: "removed"
        }
    }
}
