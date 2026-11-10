import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird

/// An email as the recipient reads it.
struct SentEmail {
    let subject: String
    let body: String
}

/// A backup run fixture with email set up, reading back the alerts its Hive sends.
struct AlertFixture {
    let runs: BackupRunFixture

    init(setUpEmail: Bool = true) async throws {
        runs = try await BackupRunFixture()
        try runs.write("hello", to: "srv/site/index.html")
        // The sample quota is bigger than the test drive, which would send its own alert in every test.
        try setQuota(nil)
        if setUpEmail { try await self.setUpEmail() }
    }

    var api: APIFixture {
        runs.api
    }

    var clock: TestClock {
        runs.clock
    }

    var store: AlertStore {
        AlertStore(database: api.signIn.database)
    }

    func setUpEmail(on fixture: APIFixture? = nil) async throws {
        let change = EmailSettingsChange(settings: EmailRoutesTests.settings, password: EmailRoutesTests.password)
        let answer = try await (fixture ?? api).send(.put, HiveEndpoint.email, json: change)
        guard answer.status == .ok else { throw APIFixtureError.unexpectedStatus(answer.status) }
    }

    func setQuota(_ bytes: Int64?) throws {
        try api.signIn.database.writer.write { database in
            try database.execute(sql: "UPDATE server SET quotaBytes = ?", arguments: [bytes])
        }
    }

    /// Works out the alerts and sends what they owe, as Hive does each minute, on `fixture`'s Hive when given.
    func check(on fixture: APIFixture? = nil) async {
        let alerts = (fixture ?? api).api.alerts
        await alerts.check()
        await alerts.mailer.sendOwed()
        await alerts.mailer.waitUntilIdle()
    }

    /// Every email sent so far, oldest first, or only those whose subject starts with `prefix`.
    func sent(on fixture: APIFixture? = nil, startingWith prefix: String = "") throws -> [SentEmail] {
        try (fixture ?? api).smtp.sessions.compactMap(\.message).map { data in
            let parsed = try ParsedMessage(data)
            return SentEmail(subject: try parsed.decodedHeader("Subject") ?? "", body: try parsed.decodedBody())
        }
        .filter { $0.subject.hasPrefix(prefix) }
    }

    /// A run that fails because its directory is gone from the server, a minute after the last unless told.
    @discardableResult
    func failingRun(after interval: TimeInterval = 60) async throws -> RunLogEntry {
        try? FileManager.default.removeItem(at: runs.source("srv/site"))
        return try await runs.runEntry(after: interval)
    }

    @discardableResult
    func succeedingRun(after interval: TimeInterval = 60) async throws -> RunLogEntry {
        try runs.write("hello", to: "srv/site/index.html")
        return try await runs.runEntry(after: interval)
    }

    /// A finished run in the job log, for failures the stand-in server can't cause.
    func recordRun(failing failure: BackupFailure?, job: BackupJob? = nil) throws {
        let job = job ?? runs.job
        let (server, now) = (runs.serverRecord, clock.now)
        try api.signIn.database.writer.write { database in
            var entry = JobLogRecord(
                id: nil,
                jobID: job.id,
                serverID: server.id,
                serverName: server.name,
                jobName: job.name,
                trigger: .scheduled,
                startedAt: now,
                finishedAt: now,
                failure: failure,
                pickedUpPartialSnapshot: false,
                directories: [],
                databases: []
            )
            try entry.insert(database)
        }
    }
}
