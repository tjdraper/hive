import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import ScoutProtocol
import Testing

struct MetricsReadingRouteTests {
    private let fixture: APIFixture
    private let server: Server
    private let scout: TestScout

    init() async throws {
        fixture = try APIFixture()
        try fixture.setAddressOptions()
        server = try await fixture.addServer()
        scout = try await fixture.enrollScout(for: server)
    }

    private var now: Int64 {
        Int64(fixture.signIn.clock.now.timeIntervalSince1970)
    }

    private func report(_ report: MetricsReport, from scout: TestScout? = nil) async throws {
        let token = try await fixture.scoutToken(scout ?? self.scout)
        let answer = try await fixture.send(.post, ScoutEndpoint.metrics, token: token, body: JSONEncoder().encode(report))
        #expect(answer.status == .noContent)
    }

    private func get<Value: Decodable>(_ path: String, as _: Value.Type) async throws -> Value {
        let answer = try await fixture.send(.get, path)
        guard answer.status == .ok else { throw APIFixtureError.unexpectedStatus(answer.status) }
        return try answer.decoded(as: Value.self)
    }

    @Test("The summary gives each server with metrics, by name, whether it's reporting, its newest figures and its last hour")
    func summary() async throws {
        // Arrange: this server, Studio Web, reports two minutes, its fullest filesystem /var; Other never reports.
        let other = try await fixture.addOtherServer()
        _ = try await fixture.enrollScout(for: other)
        let start = now - 120
        var newest = TestMetrics.sample(at: start + 60, cpuUser: 0.5, availableBytes: 2_000_000_000)
        newest.filesystems = [TestMetrics.filesystem("/", available: 60_000_000_000), TestMetrics.filesystem("/var", available: 10)]
        try await report(TestMetrics.report([TestMetrics.sample(at: start, cpuUser: 0.1), newest], sentAt: now))

        // Act
        let summaries = try await get(HiveEndpoint.metricsSummary, as: [ServerMetricsSummary].self)

        // Assert
        #expect(summaries.map(\.serverID) == [other.id, server.id])
        let reporting = try #require(summaries.last)
        #expect(reporting.reporting == .reporting)
        let latest = try #require(reporting.latest)
        #expect(latest.takenAt == start + 60)
        #expect(latest.cpu?.user == 0.5)
        #expect(latest.memory?.availableBytes == 2_000_000_000)
        #expect(latest.fullestFilesystem?.mountPoint == "/var")
        #expect(reporting.lastHour.map(\.startsAt) == [start, start + 60].map { MetricsResolution.minute.periodStart(of: $0) })
        let last = try #require(reporting.lastHour.last)
        #expect(TestMetrics.isClose(try #require(last.cpuBusy), 0.56))
        #expect(TestMetrics.isClose(try #require(last.memoryUsed), 0.75))
        #expect(summaries[0].reporting == .waiting)
        #expect(summaries[0].latest == nil)
    }

    @Test("A server silent for 3 minutes has stopped, with no sparkline an hour later, and one refused for its clock is clock ahead")
    func stoppedAndClockAhead() async throws {
        // Arrange
        let other = try await fixture.addOtherServer()
        let otherScout = try await fixture.enrollScout(for: other)
        try await report(TestMetrics.report([TestMetrics.sample(at: now)]))
        fixture.signIn.clock.advance(by: ServerMetricsSummaryReader.stoppedAfter + 1)
        let ahead = TestMetrics.report([TestMetrics.sample(at: now + 3_600)], sentAt: now + 3_600)
        let token = try await fixture.scoutToken(otherScout)
        let answer = try await fixture.send(.post, ScoutEndpoint.metrics, token: token, body: JSONEncoder().encode(ahead))
        #expect(answer.status == .unprocessableContent)

        // Act
        let summaries = try await get(HiveEndpoint.metricsSummary, as: [ServerMetricsSummary].self)

        fixture.signIn.clock.advance(by: 3_600)
        let anHourLater = try await get(HiveEndpoint.metricsSummary, as: [ServerMetricsSummary].self)

        // Assert
        #expect(summaries.map(\.reporting) == [.clockAhead, .stopped])
        #expect(summaries[1].lastHour.count == 1)
        #expect(anHourLater[1].lastHour.isEmpty)
        #expect(anHourLater[1].latest?.takenAt == summaries[1].latest?.takenAt)
    }

    @Test("A moment's processes are the nearest sample's within a day, the hour's busiest after, and nothing without either")
    func processesAtAMoment() async throws {
        // Arrange: samples a minute apart with their own groups, then the hourly pass once their hour is
        // past. The hour before has nothing.
        let start = MetricsResolution.hour.periodStart(of: now) - 3_600
        let samples = (0 ..< 3).map { index in
            TestMetrics.sample(at: start + Int64(index) * 60, processGroups: [
                ProcessGroup(command: "worker\(index)", user: "www-data", count: 1, cpuCores: Double(index), ownMemoryBytes: 1_000),
            ])
        }
        try await report(TestMetrics.report(samples, sentAt: now))
        fixture.api.metricsUpkeep.runOnce()
        let samplesKept = MetricsUpkeep.processSampleKeptSeconds

        // Act
        let nearest = try await get(HiveEndpoint.processes(ofServer: server.id, at: start + 70), as: ProcessMoment.self)
        let tooFar = try await get(
            HiveEndpoint.processes(ofServer: server.id, at: start - ProcessMomentReader.nearestSampleSeconds - 1),
            as: ProcessMoment.self
        )
        fixture.signIn.clock.advance(by: TimeInterval(samplesKept + 3_600))
        fixture.api.metricsUpkeep.runOnce()
        let hourly = try await get(HiveEndpoint.processes(ofServer: server.id, at: start + 70), as: ProcessMoment.self)

        // Assert
        guard case .sample(let takenAt, let groups, _) = nearest else {
            Issue.record("Not a sample: \(nearest)")
            return
        }
        #expect(takenAt == start + 60)
        #expect(groups.map(\.command) == ["worker1"])
        #expect(tooFar == .notKept)
        guard case .hour(let hour, let hourGroups) = hourly else {
            Issue.record("Not an hour: \(hourly)")
            return
        }
        #expect(hour == start)
        #expect(hourGroups.map(\.command) == ["worker2", "worker1", "worker0"])
    }

    @Test("Backup runs in a range are on the server's clock, and only that server's")
    func backupRunMarks() async throws {
        // Arrange: the server's clock is 30 seconds ahead of Hive's.
        try await report(TestMetrics.report([TestMetrics.sample(at: now)], sentAt: now + 30))
        let job = try await fixture.addJob(to: server)
        let other = try await fixture.addOtherServer()
        let otherJob = try await fixture.addJob(to: other)
        let hiveNow = fixture.signIn.clock.now
        try await fixture.signIn.database.writer.write { database in
            let runs = [(job.id, server.id, 10.0), (job.id, server.id, 120.0), (otherJob.id, other.id, 10.0)]
            for (jobID, serverID, minutesAgo) in runs {
                let startedAt = hiveNow.addingTimeInterval(-minutesAgo * 60)
                var entry = JobLogRecord(
                    id: nil, jobID: jobID, serverID: serverID, serverName: "", jobName: "Site", trigger: .scheduled,
                    startedAt: startedAt, finishedAt: startedAt.addingTimeInterval(60),
                    failure: nil, pickedUpPartialSnapshot: false, directories: [], databases: []
                )
                try entry.insert(database)
            }
        }

        // Act
        let path = HiveEndpoint.backupRunMarks(ofServer: server.id, from: now - 3_600, to: now + 30)
        let marks = try await get(path, as: [BackupRunMark].self)

        // Assert
        let expected = BackupRunMark(jobID: job.id, jobName: "Site", startedAt: now - 600 + 30, finishedAt: now - 540 + 30, failure: nil)
        #expect(marks == [expected])
    }

    @Test("Only a report's current sample reaches live updates, never a backlog's older ones")
    func backlogNeverLive() async throws {
        // Arrange
        var seen = fixture.api.metricsBoard.listen().seen

        // Act
        try await report(TestMetrics.report([TestMetrics.sample(at: now - 600), TestMetrics.sample(at: now - 590)], sentAt: now))
        let afterBacklog = fixture.api.metricsBoard.changes(since: &seen)
        try await report(TestMetrics.report([TestMetrics.sample(at: now, cpuUser: 0.7)], sentAt: now))
        let afterCurrent = fixture.api.metricsBoard.changes(since: &seen)

        // Assert
        #expect(afterBacklog.isEmpty)
        #expect(afterCurrent.map(\.takenAt) == [now])
        #expect(afterCurrent.first?.cpu?.user == 0.7)
    }

    @Test(
        "A series asked for with an unknown figure, a range backwards or too long, or for no such server, is refused",
        arguments: [
            ("figures=nope", HTTPResponse.Status.badRequest),
            ("figures=", .badRequest),
            ("from=10&to=5", .badRequest),
            ("longest", .badRequest),
        ] as [(String, HTTPResponse.Status)]
    )
    func badSeriesRequests(query: String, expected: HTTPResponse.Status) async throws {
        // Arrange
        let base = "\(HiveEndpoint.metrics(ofServer: server.id))/series"
        let path = switch query {
        case "longest":
            HiveEndpoint.metricsSeries(ofServer: server.id, from: 0, to: HiveEndpoint.longestMetricsRange + 1, figures: [.cpuUser])
        case "from=10&to=5": "\(base)?from=10&to=5&figures=cpuUser"
        default: "\(base)?from=0&to=3600&\(query)"
        }

        // Act
        let answer = try await fixture.send(.get, path)
        let unknown = try await fixture.send(.get, HiveEndpoint.metricsSeries(ofServer: UUID(), from: 0, to: 3_600, figures: [.cpuUser]))

        // Assert
        #expect(answer.status == expected)
        #expect(unknown.status == .notFound)
    }
}
