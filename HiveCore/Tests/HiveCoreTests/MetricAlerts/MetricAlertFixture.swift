import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import ScoutProtocol

/// A Hive with email set up and servers whose Scouts have enrolled, reading back the alerts it sends
/// about their figures. Its clock moves on only when a test moves it.
struct MetricAlertFixture {
    let api: APIFixture
    let web: Server
    let other: Server

    /// Past the grace after Hive starts, unless told otherwise.
    init(pastStartGrace: Bool = true) async throws {
        api = try APIFixture()
        try api.setAddressOptions()
        web = try await api.addServer()
        other = try await api.addOtherServer()
        _ = try await api.enrollScout(for: web)
        _ = try await api.enrollScout(for: other)
        let change = EmailSettingsChange(settings: EmailRoutesTests.settings, password: EmailRoutesTests.password)
        let answer = try await api.send(.put, HiveEndpoint.email, json: change)
        guard answer.status == .ok else { throw APIFixtureError.unexpectedStatus(answer.status) }
        if pastStartGrace { clock.advance(by: ReportingGrace.length) }
        // Samples on the server's clock fall on 10-second marks, as Scout takes them.
        clock.advance(by: 10 - clock.now.timeIntervalSince1970.truncatingRemainder(dividingBy: 10))
    }

    var clock: TestClock {
        api.signIn.clock
    }

    var now: Int64 {
        Int64(clock.now.timeIntervalSince1970)
    }

    /// The same Hive started again, with its store, keys and metrics.
    func restarted() throws -> APIFixture {
        try APIFixture(signIn: api.signIn, sealer: api.sealer, metrics: api.metricsDatabase)
    }

    /// A report sent now, as Scout sends one, kept for `server`.
    @discardableResult
    func report(_ samples: [MetricsSample], for server: Server? = nil, sentAt: Int64? = nil, on fixture: APIFixture? = nil)
        throws -> MetricsReportOutcome {
        let report = MetricsReport(protocolVersion: ScoutProtocolVersion.current, sentAt: sentAt ?? now, samples: samples, minutes: [])
        return (fixture ?? api).api.metricsReports.keep(try JSONEncoder().encode(report), forServer: (server ?? web).id)
    }

    /// When the servers last started, so samples' uptimes agree with each other.
    static let bootedAt = TestMetrics.start - 1_000

    /// Plausible figures taken now, by a server that hasn't restarted.
    func sample(at takenAt: Int64? = nil) -> MetricsSample {
        let takenAt = takenAt ?? now
        var sample = TestMetrics.sample(at: takenAt)
        sample.server.uptimeSeconds = Double(takenAt - Self.bootedAt)
        return sample
    }

    /// A sample every 10 seconds for `minutes`, each sent as it's taken, for `server` or both servers.
    func reportLive(
        for minutes: Double,
        servers: [Server]? = nil,
        on fixture: APIFixture? = nil,
        _ change: (inout MetricsSample) -> Void = { _ in /* As `TestMetrics.sample` makes it. */ }
    ) throws {
        for _ in 0 ..< Int(minutes * 6) {
            clock.advance(by: 10)
            for server in servers ?? [web] {
                var sample = self.sample()
                change(&sample)
                try report([sample], for: server, on: fixture)
            }
        }
    }

    /// Works out the alerts and sends what they owe, as Hive does each minute.
    func check(on fixture: APIFixture? = nil) async {
        let alerts = (fixture ?? api).api.alerts
        await alerts.check()
        await alerts.mailer.sendOwed()
        await alerts.mailer.waitUntilIdle()
    }

    /// Every email sent so far, oldest first, by any Hive sharing this one's mail server.
    func sent(on fixture: APIFixture? = nil) throws -> [SentEmail] {
        try (fixture ?? api).smtp.sessions.compactMap(\.message).map { data in
            let parsed = try ParsedMessage(data)
            return SentEmail(subject: try parsed.decodedHeader("Subject") ?? "", body: try parsed.decodedBody())
        }
    }

    func subjects(on fixture: APIFixture? = nil) throws -> [String] {
        try sent(on: fixture).map(\.subject)
    }

    /// The server's alerts, as the dashboard reads them.
    func alerts(of server: Server? = nil) throws -> [MetricAlert] {
        try api.api.metricsSummaries.summaries().first { $0.serverID == (server ?? web).id }?.alerts ?? []
    }
}

extension MetricsSample {
    /// User, system, I/O wait and steal together.
    mutating func setCPUBusy(_ share: Double, steal: Double = 0) {
        cpu?.use = CPUUse(user: share - steal, system: 0, ioWait: 0, steal: steal)
    }

    /// Of `TestMetrics.memory`'s total.
    mutating func setMemoryAvailable(_ share: Double) {
        memory?.availableBytes = UInt64(8_000_000_000 * share)
    }

    /// Of the root filesystem's usable space.
    mutating func setRootUsed(_ share: Double) {
        filesystems = [TestMetrics.filesystem("/", available: UInt64(100_000_000_000 * (1 - share)))]
    }
}
