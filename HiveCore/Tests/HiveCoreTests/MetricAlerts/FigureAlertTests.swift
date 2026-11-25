import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import ScoutProtocol
import Testing

struct FigureAlertTests {
    private static let day: TimeInterval = 24 * 60 * 60

    @Test("CPU busy for 15 minutes sends one email at 15 minutes and not before, and none again while it stays busy")
    func cpuBusy() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()

        // Act
        try fixture.reportLive(for: 14.5) { $0.setCPUBusy(0.95) }
        await fixture.check()
        let early = try fixture.subjects()
        try fixture.reportLive(for: 0.5) { $0.setCPUBusy(0.95) }
        await fixture.check()
        try fixture.reportLive(for: 30) { $0.setCPUBusy(0.95) }
        fixture.clock.advance(by: Self.day)
        try fixture.reportLive(for: 1) { $0.setCPUBusy(0.95) }
        await fixture.check()

        // Assert
        #expect(early.isEmpty)
        let sent = try fixture.sent()
        #expect(sent.map(\.subject) == ["CPU busy: “Studio Web”"])
        #expect(sent.first?.body.contains("95% busy") == true)
        #expect(try fixture.alerts() == [.cpuBusy])
        #expect(try fixture.api.api.metricsState.state(ofServer: fixture.web.id)?.alerts == [.cpuBusy])
        #expect(try fixture.api.api.metricsState.state(ofServer: fixture.other.id)?.alerts == [])
    }

    @Test("Busy CPU ends only after an hour within its limits, and a later spell sends a second email")
    func cpuClearsAfterAnHour() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        try fixture.reportLive(for: 15) { $0.setCPUBusy(0.95) }
        await fixture.check()

        // Act
        try fixture.reportLive(for: 50)
        let afterFifty = try fixture.alerts()
        try fixture.reportLive(for: 30)
        let afterEighty = try fixture.alerts()
        try fixture.reportLive(for: 15) { $0.setCPUBusy(0.95) }
        await fixture.check()

        // Assert
        #expect(afterFifty == [.cpuBusy])
        #expect(afterEighty.isEmpty)
        #expect(try fixture.subjects() == ["CPU busy: “Studio Web”", "CPU busy: “Studio Web”"])
    }

    @Test("Steal and load each count as a busy CPU on their own")
    func stealAndLoad() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()

        // Act
        for _ in 0 ..< 15 * 6 {
            fixture.clock.advance(by: 10)
            var stolen = fixture.sample()
            stolen.setCPUBusy(0.3, steal: 0.25)
            var loaded = fixture.sample()
            loaded.cpu?.load?.oneMinute = 9.2
            try fixture.report([stolen], for: fixture.web)
            try fixture.report([loaded], for: fixture.other)
        }
        await fixture.check()

        // Assert
        let bodies = try fixture.sent().map(\.body)
        #expect(bodies.count == 2)
        #expect(bodies.contains { $0.contains("took 25% of its CPU time") })
        #expect(bodies.contains { $0.contains("load was 2.3 for each core") })
    }

    @Test("Memory available under 10% for 10 minutes sends one email at 10 minutes and not before")
    func memoryShort() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        try fixture.reportLive(for: 1)

        // Act
        try fixture.reportLive(for: 9) { $0.setMemoryAvailable(0.08) }
        await fixture.check()
        let early = try fixture.subjects()
        try fixture.reportLive(for: 1) { $0.setMemoryAvailable(0.08) }
        await fixture.check()

        // Assert
        #expect(early.isEmpty)
        #expect(try fixture.subjects() == ["Short of memory: “Studio Web”"])
    }

    @Test("Swapping in steadily counts as short of memory, with plenty available")
    func swapping() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()

        // Act
        try fixture.reportLive(for: 10) { $0.memory?.swapping = Swapping(pagesInPerSecond: 400, pagesOutPerSecond: 0) }
        await fixture.check()

        // Assert
        let sent = try fixture.sent()
        #expect(sent.map(\.subject) == ["Short of memory: “Studio Web”"])
        #expect(sent.first?.body.contains("swapped in 400 pages a second") == true)
    }

    @Test("A filesystem past its limit sends one email, a reminder a day later, and ends once it has room again")
    func filesystemFilling() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()

        // Act
        try fixture.reportLive(for: 1) { $0.setRootUsed(0.89) }
        await fixture.check()
        let underLimit = try fixture.subjects()
        try fixture.reportLive(for: 5) { $0.setRootUsed(0.95) }
        await fixture.check()
        fixture.clock.advance(by: Self.day)
        try fixture.reportLive(for: 1) { $0.setRootUsed(0.95) }
        await fixture.check()
        let whileFull = try fixture.alerts()
        try fixture.reportLive(for: 1) { $0.setRootUsed(0.87) }
        let atMargin = try fixture.alerts()
        try fixture.reportLive(for: 1) { $0.setRootUsed(0.5) }

        // Assert
        #expect(underLimit.isEmpty)
        #expect(try fixture.subjects() == ["Disk filling up: “/” on “Studio Web”", "Still filling up: “/” on “Studio Web”"])
        #expect(whileFull == [.filesystemFilling(mountPoint: "/")])
        #expect(atMargin == [.filesystemFilling(mountPoint: "/")])
        #expect(try fixture.alerts().isEmpty)
    }

    @Test("A filesystem out of inodes, with space left, sends an email about its inodes")
    func inodes() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()

        // Act
        try fixture.reportLive(for: 1) { $0.filesystems[0].space?.inodes = InodeCounts(used: 960, free: 40) }
        await fixture.check()

        // Assert
        let sent = try fixture.sent()
        #expect(sent.map(\.subject) == ["Disk filling up: “/” on “Studio Web”"])
        #expect(sent.first?.body.contains("96% of the inodes") == true)
        #expect(sent.first?.body.contains("is 50% full") == false)
    }

    @Test("A server that restarted sends one email, and its clock being set right sends none")
    func restarted() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        try fixture.reportLive(for: 1)

        // Act
        fixture.clock.advance(by: 10)
        var corrected = fixture.sample()
        corrected.server.uptimeSeconds = (corrected.server.uptimeSeconds ?? 0) + 120
        try fixture.report([corrected])
        await fixture.check()
        let afterCorrection = try fixture.subjects()
        for uptime in [30.0, 40, 50] {
            fixture.clock.advance(by: 10)
            var sample = fixture.sample()
            sample.server.uptimeSeconds = uptime
            try fixture.report([sample])
        }
        await fixture.check()

        // Assert
        #expect(afterCorrection.isEmpty)
        #expect(try fixture.subjects() == ["Restarted: “Studio Web”"])
    }

    @Test("A backlog from a Scout that was cut off doesn't send alerts for what was true while it was away")
    func backlog() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        try fixture.reportLive(for: 1)
        fixture.clock.advance(by: 2 * 3_600)
        let cutOffAt = fixture.now - 2 * 3_600

        // Act
        try fixture.report([fixture.sample()])
        let backlog = (1 ... 30 * 6).map { step in
            var sample = fixture.sample(at: cutOffAt + Int64(step) * 10)
            sample.setCPUBusy(0.99)
            sample.setMemoryAvailable(0.01)
            sample.setRootUsed(0.99)
            sample.server.uptimeSeconds = Double(step * 10)
            return sample
        }
        for batch in stride(from: 0, to: backlog.count, by: MetricsReport.largestSampleCount) {
            try fixture.report(Array(backlog[batch ..< min(batch + MetricsReport.largestSampleCount, backlog.count)]))
        }
        try fixture.reportLive(for: 1)
        await fixture.check()

        // Assert
        #expect(try fixture.metricsRows() > 30 * 6)
        #expect(try fixture.subjects().isEmpty)
        #expect(try fixture.alerts().isEmpty)
    }

    @Test("A duration counts samples from before Hive restarted, and an alert open before it isn't emailed again")
    func acrossRestart() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        try fixture.reportLive(for: 10) { $0.setCPUBusy(0.95); $0.setRootUsed(0.95) }
        await fixture.check()

        // Act
        let restarted = try fixture.restarted()
        try fixture.reportLive(for: 5, on: restarted) { $0.setCPUBusy(0.95); $0.setRootUsed(0.95) }
        await fixture.check(on: restarted)

        // Assert
        #expect(try fixture.subjects() == ["Disk filling up: “/” on “Studio Web”"])
        #expect(try fixture.subjects(on: restarted) == ["CPU busy: “Studio Web”"])
    }

    @Test("A server's own limits replace the defaults, and setting the defaults again follows them")
    func ownLimits() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        var limits = MetricAlertLimits.defaults
        limits.cpuBusyPercent = 50
        limits.cpuMinutes = 5
        let path = HiveEndpoint.metricAlertLimits(ofServer: fixture.web.id)

        // Act
        let put = try await fixture.api.send(.put, path, json: limits)
        try fixture.reportLive(for: 5) { $0.setCPUBusy(0.6) }
        await fixture.check()
        let reset = try await fixture.api.send(.put, path, json: MetricAlertLimits.defaults)
        let read = try await fixture.api.send(.get, path)

        // Assert
        #expect(put.status == .ok)
        #expect(try fixture.subjects() == ["CPU busy: “Studio Web”"])
        #expect(reset.status == .ok)
        #expect(try read.decoded(as: MetricAlertLimits.self) == .defaults)
        let events = try fixture.api.auditEvents().prefix(2)
        #expect(Array(events) == [
            .server(serverID: fixture.web.id, serverName: "Studio Web", change: .metricAlertLimits(old: limits, new: .defaults)),
            .server(serverID: fixture.web.id, serverName: "Studio Web", change: .metricAlertLimits(old: .defaults, new: limits)),
        ])
    }

    @Test("Limits out of range are refused, changing nothing, and an unknown server's are not found")
    func refusesLimits() async throws {
        // Arrange
        let fixture = try await MetricAlertFixture()
        var limits = MetricAlertLimits.defaults
        limits.memoryMinutes = 0
        let before = try fixture.api.auditEvents()

        // Act
        let refused = try await fixture.api.send(.put, HiveEndpoint.metricAlertLimits(ofServer: fixture.web.id), json: limits)
        let unknown = try await fixture.api.send(.get, HiveEndpoint.metricAlertLimits(ofServer: UUID()))

        // Assert
        #expect(refused.status == .badRequest)
        #expect(unknown.status == .notFound)
        #expect(try fixture.api.auditEvents() == before)
    }
}

extension MetricAlertFixture {
    /// The web server's 10-second rows.
    func metricsRows() throws -> Int {
        try api.metricsDatabase.cpuUser(ofServer: web.id).count
    }
}
