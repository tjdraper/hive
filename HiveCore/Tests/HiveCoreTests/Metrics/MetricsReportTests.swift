import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import ScoutProtocol
import Testing

/// Which of a sample's lists `figureLimits` fills to its limit.
enum FigureLimit: CaseIterable, Sendable {
    case filesystems
    case disks
    case interfaces
    case processGroups
    case containers
    case services

    var limit: Int {
        switch self {
        case .filesystems: MetricsReportCheck.largestFilesystemCount
        case .disks: MetricsReportCheck.largestDiskCount
        case .interfaces: MetricsReportCheck.largestInterfaceCount
        case .processGroups: MetricsReportCheck.largestProcessGroupCount
        case .containers, .services: MetricsReportCheck.largestCgroupCount
        }
    }

    func sample(at takenAt: Int64, count: Int) -> MetricsSample {
        var sample = TestMetrics.sample(at: takenAt)
        switch self {
        case .filesystems:
            sample.filesystems = (0 ..< count).map { TestMetrics.filesystem("/fs\($0)", available: 1) }
        case .disks:
            sample.disks = (0 ..< count).map { DiskFigures(name: "d\($0)", activity: nil) }
        case .interfaces:
            sample.networkInterfaces = (0 ..< count).map { NetworkInterfaceFigures(name: "i\($0)", traffic: nil) }
        case .processGroups:
            sample.processes?.groups = (0 ..< count).map {
                ProcessGroup(command: "c\($0)", user: "u", count: 1, cpuCores: 0, ownMemoryBytes: 0)
            }
        case .containers:
            sample.containers = TestMetrics.cgroups((0 ..< count).map { TestMetrics.containerID($0) })
        case .services:
            sample.services = TestMetrics.cgroups((0 ..< count).map { "s\($0).service" })
        }
        return sample
    }
}

struct MetricsReportTests {
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

    private func send(_ report: MetricsReport, token: String) async throws -> APIAnswer {
        try await send(JSONEncoder().encode(report), token: token)
    }

    private func send(_ body: Data, token: String) async throws -> APIAnswer {
        try await fixture.send(.post, ScoutEndpoint.metrics, token: token, body: body)
    }

    private func refusal(_ answer: APIAnswer) throws -> ScoutRefusal.Reason {
        try answer.decoded(as: ScoutRefusal.self).reason
    }

    private func storedTimes() throws -> [Int64] {
        try fixture.metricsDatabase.writer.read { try Int64.fetchAll($0, sql: "SELECT startsAt FROM serverTenSeconds ORDER BY startsAt") }
    }

    @Test("A Scout's samples are kept for the server its session is for, and never another's")
    func keptForOwnServer() async throws {
        // Arrange
        let other = try await fixture.addOtherServer()
        let otherScout = try await fixture.enrollScout(for: other)

        // Act
        let answer = try await send(TestMetrics.report([TestMetrics.sample(at: now, cpuUser: 0.1)]), token: fixture.scoutToken(scout))
        let otherAnswer = try await send(
            TestMetrics.report([TestMetrics.sample(at: now, cpuUser: 0.7)]),
            token: fixture.scoutToken(otherScout)
        )

        // Assert
        #expect(answer.status == .noContent)
        #expect(otherAnswer.status == .noContent)
        #expect(try fixture.metricsDatabase.cpuUser(ofServer: server.id) == [0.1])
        #expect(try fixture.metricsDatabase.cpuUser(ofServer: other.id) == [0.7])
    }

    @Test("Each request records the server's clock offset and what it said about itself, without writing to Hive's store")
    func recordsOffsetAndFacts() async throws {
        // Arrange
        let token = try await fixture.scoutToken(scout)
        let signedInAt = fixture.signIn.clock.now
        fixture.signIn.clock.advance(by: 5)

        // Act
        let answer = try await send(TestMetrics.report([TestMetrics.sample(at: now + 40)], sentAt: now + 42), token: token)

        // Assert
        #expect(answer.status == .noContent)
        let record = try #require(try fixture.api.metrics.server(server.id))
        #expect(record.clockOffsetSeconds == 42)
        #expect(record.lastReportAt == fixture.signIn.clock.now)
        #expect(record.lastSampleAt == now + 40)
        #expect(record.scoutVersion == "0.1.0")
        #expect(record.distribution == "Debian GNU/Linux 12 (bookworm)")
        #expect(record.processesHidden == false)
        #expect(try fixture.api.scouts.scout(forServer: server.id)?.lastSeenAt == signedInAt)
    }

    @Test("A device's session, or none, can't send samples")
    func deviceSessionRefused() async throws {
        // Arrange
        let body = try JSONEncoder().encode(TestMetrics.report([TestMetrics.sample(at: now)]))

        // Act
        let asDevice = try await send(body, token: fixture.token())
        let unsigned = try await send(body, token: "not-a-session")

        // Assert
        #expect(asDevice.status == .forbidden)
        #expect(unsigned.status == .unauthorized)
        #expect(try fixture.metricsDatabase.count("metricsServer") == 0)
    }

    @Test("A Scout's open session can't send samples once its server's metrics are removed")
    func revokedScoutRefused() async throws {
        // Arrange
        let token = try await fixture.scoutToken(scout)
        _ = try await fixture.send(.delete, HiveEndpoint.metrics(ofServer: server.id))

        // Act
        let answer = try await send(TestMetrics.report([TestMetrics.sample(at: now)]), token: token)

        // Assert
        #expect(answer.status == .unauthorized)
        #expect(try fixture.metricsDatabase.count("serverTenSeconds") == 0)
    }

    @Test("The protocol version before the current one is accepted, and the one before that told to update")
    func protocolVersions() async throws {
        // Arrange
        let token = try await fixture.scoutToken(scout)
        let current = ScoutProtocolVersion.current

        // Act
        let previous = try await send(TestMetrics.report([TestMetrics.sample(at: now)], protocolVersion: current - 1), token: token)
        let tooOld = try await send(TestMetrics.report([TestMetrics.sample(at: now - 10)], protocolVersion: current - 2), token: token)

        // Assert
        #expect(previous.status == .noContent)
        #expect(tooOld.status == .conflict)
        #expect(try tooOld.decoded(as: ScoutProtocolMismatch.self).hiveProtocolVersion == current)
        #expect(try storedTimes() == [now])
    }

    @Test("A sample further ahead of Hive's clock, or of the time Scout sent it, than Hive allows is refused as clock ahead")
    func clockAhead() async throws {
        // Arrange
        let token = try await fixture.scoutToken(scout)
        let lead = MetricsReportCheck.largestLeadSeconds

        // Act
        let aheadOfHive = try await send(TestMetrics.report([TestMetrics.sample(at: now + lead + 10)]), token: token)
        let aheadOfSending = try await send(
            TestMetrics.report([TestMetrics.sample(at: now - 600 + lead + 10)], sentAt: now - 600),
            token: token
        )
        let refusedRecord = try fixture.api.metrics.server(server.id)
        let atHiveLimit = try await send(TestMetrics.report([TestMetrics.sample(at: now + lead)]), token: token)
        let atSendingLimit = try await send(TestMetrics.report([TestMetrics.sample(at: now - 600 + lead)], sentAt: now - 600), token: token)

        // Assert
        #expect(aheadOfHive.status == .unprocessableContent)
        #expect(try refusal(aheadOfHive) == .clockAhead)
        #expect(try refusal(aheadOfSending) == .clockAhead)
        #expect(refusedRecord?.lastRefusal == ScoutRefusal.Reason.clockAhead.rawValue)
        #expect(atHiveLimit.status == .noContent)
        #expect(atSendingLimit.status == .noContent)
        #expect(try fixture.api.metrics.server(server.id)?.lastRefusal == nil)
        #expect(try storedTimes() == [now - 600 + lead, now + lead])
    }

    @Test("Samples older than a day are left out, and a request holding only those is refused")
    func tooOld() async throws {
        // Arrange
        let token = try await fixture.scoutToken(scout)
        let dayAgo = now - MetricsReportCheck.oldestSeconds

        // Act
        let onlyOld = try await send(TestMetrics.report([TestMetrics.sample(at: dayAgo - 10)], sentAt: now), token: token)
        let mixed = try await send(
            TestMetrics.report([TestMetrics.sample(at: dayAgo - 10), TestMetrics.sample(at: dayAgo), TestMetrics.sample(at: now)]),
            token: token
        )

        // Assert
        #expect(onlyOld.status == .unprocessableContent)
        #expect(try refusal(onlyOld) == .tooOld)
        #expect(mixed.status == .noContent)
        #expect(try storedTimes() == [dayAgo, now])
    }

    @Test("A request is accepted with the most samples and minutes Hive takes, and refused with one more")
    func sampleAndMinuteCounts() async throws {
        // Arrange
        let token = try await fixture.scoutToken(scout)
        let samples = (0 ... MetricsReport.largestSampleCount).map { TestMetrics.sample(at: now - Int64($0) * 10) }
        let minutes = (0 ... MetricsReport.largestMinuteCount).map {
            TestMetrics.minute(at: now - 3_600 - Int64($0) * 60, average: 0.2, highest: 0.4, lowestAvailable: 1_000_000_000)
        }

        // Act
        let tooManySamples = try await send(TestMetrics.report(samples), token: token)
        let tooManyMinutes = try await send(TestMetrics.report(minutes: minutes, sentAt: now), token: token)
        let mostSamples = try await send(TestMetrics.report(Array(samples.dropLast())), token: token)
        let mostMinutes = try await send(TestMetrics.report(minutes: Array(minutes.dropLast()), sentAt: now), token: token)

        // Assert
        #expect(try refusal(tooManySamples) == .tooManySamples)
        #expect(try refusal(tooManyMinutes) == .tooManySamples)
        #expect(mostSamples.status == .noContent)
        #expect(mostMinutes.status == .noContent)
        #expect(try storedTimes().count == MetricsReport.largestSampleCount)
    }

    @Test("Each kind of figure is accepted at Hive's limit in a sample and refused over it", arguments: FigureLimit.allCases)
    func figureLimits(_ kind: FigureLimit) async throws {
        // Arrange
        let token = try await fixture.scoutToken(scout)

        // Act
        let over = try await send(TestMetrics.report([kind.sample(at: now - 10, count: kind.limit + 1)]), token: token)
        let atLimit = try await send(TestMetrics.report([kind.sample(at: now, count: kind.limit)]), token: token)

        // Assert
        #expect(over.status == .unprocessableContent)
        #expect(try refusal(over) == .tooManyFigures)
        #expect(atLimit.status == .noContent)
        #expect(try storedTimes() == [now])
    }

    @Test("A server brings in as many new names in a day as Hive takes, one more is refused, and more are taken a day later")
    func newNamesInADay() async throws {
        // Arrange
        let token = try await fixture.scoutToken(scout)
        func sample(at takenAt: Int64, disks: Int) -> MetricsSample {
            var sample = TestMetrics.sample(at: takenAt, filesystems: (0 ..< 30).map { "/fs\($0)" })
            sample.disks = (0 ..< disks).map { DiskFigures(name: "d\($0)", activity: nil) }
            return sample
        }
        // 30 filesystems, 19 disks and `eth0`.
        let atLimit = sample(at: now, disks: 19)

        // Act
        let first = try await send(TestMetrics.report([atLimit]), token: token)
        fixture.signIn.clock.advance(by: 10)
        let oneMore = try await send(TestMetrics.report([sample(at: now, disks: 20)]), token: token)
        let refusedAt = now
        fixture.signIn.clock.advance(by: 86_400)
        let dayLater = try await send(TestMetrics.report([sample(at: now, disks: 20)]), token: fixture.scoutToken(scout))

        // Assert
        #expect(first.status == .noContent)
        #expect(try refusal(oneMore) == .tooManyNewNames)
        #expect(dayLater.status == .noContent)
        #expect(try !storedTimes().contains(refusedAt))
        #expect(try fixture.metricsDatabase.count("metricsName") == MetricsReportCheck.largestNewNameCountPerDay + 1)
    }

    @Test("A container ID that isn't 64 lowercase hex digits is refused, in the containers and in the process groups")
    func containerIDs() async throws {
        // Arrange
        let token = try await fixture.scoutToken(scout)
        let good = TestMetrics.containerID(0xABC_DEF)
        var short = TestMetrics.sample(at: now - 30)
        short.containers = TestMetrics.cgroups([String(good.dropLast())])
        var capitals = TestMetrics.sample(at: now - 20)
        capitals.containers = TestMetrics.cgroups([good.uppercased()])
        var inProcesses = TestMetrics.sample(at: now - 10)
        inProcesses.processes?.groups = [
            ProcessGroup(command: "sh", user: "0", containerID: "../\(good)", count: 1, cpuCores: 0, ownMemoryBytes: 0),
        ]
        var accepted = TestMetrics.sample(at: now)
        accepted.containers = TestMetrics.cgroups([good])

        // Act
        var answers: [APIAnswer] = []
        for sample in [short, capitals, inProcesses] {
            answers.append(try await send(TestMetrics.report([sample]), token: token))
        }
        let acceptedAnswer = try await send(TestMetrics.report([accepted]), token: token)

        // Assert
        for answer in answers {
            #expect(try refusal(answer) == .valueOutOfRange)
        }
        #expect(acceptedAnswer.status == .noContent)
        #expect(try storedTimes() == [now])
    }

    @Test("A figure out of its range, or a name with a control character, is refused, and one at the end of its range accepted")
    func valuesInRange() async throws {
        // Arrange
        let token = try await fixture.scoutToken(scout)
        var badName = TestMetrics.sample(at: now - 20)
        badName.filesystems = [TestMetrics.filesystem("/da\nta", available: 1)]
        let encoded = try JSONEncoder().encode(TestMetrics.report([TestMetrics.sample(at: now - 30)]))
        let negativeBytes = try #require(String(bytes: encoded, encoding: .utf8))
            .replacingOccurrences(of: "\"totalBytes\":8000000000", with: "\"totalBytes\":-1")

        // Act
        let overOne = try await send(TestMetrics.report([TestMetrics.sample(at: now - 10, cpuUser: 1.5)]), token: token)
        let controlCharacter = try await send(TestMetrics.report([badName]), token: token)
        let negative = try await send(Data(negativeBytes.utf8), token: token)
        let atOne = try await send(TestMetrics.report([TestMetrics.sample(at: now, cpuUser: 1)]), token: token)

        // Assert
        #expect(try refusal(overOne) == .valueOutOfRange)
        #expect(try refusal(controlCharacter) == .valueOutOfRange)
        #expect(try refusal(negative) == .valueOutOfRange)
        #expect(atOne.status == .noContent)
        #expect(try storedTimes() == [now])
    }

    @Test("A Scout may send as often as Hive takes in a minute, is turned away once more, and taken again a minute later")
    func sendingTooOften() async throws {
        // Arrange
        let token = try await fixture.scoutToken(scout)
        var statuses: [HTTPResponse.Status] = []

        // Act
        for _ in 0 ..< MetricsRateLimiter.largestRequestsPerMinute {
            statuses.append(try await send(TestMetrics.report(), token: token).status)
        }
        let oneMore = try await send(TestMetrics.report(), token: token)
        fixture.signIn.clock.advance(by: 60)
        let minuteLater = try await send(TestMetrics.report(), token: token)

        // Assert
        #expect(statuses.allSatisfy { $0 == .noContent })
        #expect(oneMore.status == .tooManyRequests)
        #expect(minuteLater.status == .noContent)
    }

    @Test("A request as large as Hive reads is kept, and a larger one refused as too large")
    func requestSize() async throws {
        // Arrange
        let token = try await fixture.scoutToken(scout)
        let report = try JSONEncoder().encode(TestMetrics.report([TestMetrics.sample(at: now)]))
        // Leading whitespace keeps it valid JSON.
        let atLimit = Data(repeating: 0x20, count: MetricsReportCheck.largestBody - report.count) + report

        // Act
        let over = try await send(Data(" ".utf8) + atLimit, token: token)
        let kept = try await send(atLimit, token: token)

        // Assert
        #expect(try refusal(over) == .tooLarge)
        #expect(kept.status == .noContent)
        #expect(try storedTimes() == [now])
    }

    @Test("Removing a server removes its metrics history, and removing only its metrics keeps it")
    func historyOnRemoval() async throws {
        // Arrange
        let other = try await fixture.addOtherServer()
        let otherScout = try await fixture.enrollScout(for: other)
        _ = try await send(TestMetrics.report([TestMetrics.sample(at: now)]), token: fixture.scoutToken(scout))
        _ = try await send(TestMetrics.report([TestMetrics.sample(at: now)]), token: fixture.scoutToken(otherScout))

        // Act
        let metricsRemoved = try await fixture.send(.delete, HiveEndpoint.metrics(ofServer: server.id))
        let serverRemoved = try await fixture.send(.delete, HiveEndpoint.server(other.id))

        // Assert
        #expect(metricsRemoved.status == .noContent)
        #expect(serverRemoved.status == .noContent)
        #expect(try fixture.metricsDatabase.cpuUser(ofServer: server.id).count == 1)
        #expect(try fixture.api.metrics.server(other.id) == nil)
        #expect(try fixture.metricsDatabase.count("serverTenSeconds") == 1)
    }
}
