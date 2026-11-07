import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

struct JobLogTests {
    @Test("Each run is in the job log, newest first, with each directory and database, how long each took and why it failed")
    func entries() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        _ = try await fixture.run()
        fixture.databaseServer.answer(output: Data(), error: RecordedDumpOutput.mariadbWrongPassword, status: 2)

        // Act
        _ = try await fixture.run()
        let page = try await fixture.jobLog()

        // Assert
        #expect(page.nextBefore == nil)
        let (failed, succeeded) = (page.runs[0], page.runs[1])
        #expect(failed.id > succeeded.id)
        #expect(failed.run.failure == .databaseLoginRefused)
        #expect(failed.run.databases.map(\.failure) == [.databaseLoginRefused])
        #expect(succeeded.run.failure == nil)
        #expect(succeeded.run.directories.map(\.folder) == ["site"])
        #expect(succeeded.run.directories.first?.filesTransferred == 1)
        #expect(succeeded.run.databases.map(\.name) == ["site"])
        #expect(succeeded.run.finishedAt != nil)
        #expect(succeeded.trigger == .runNow)
        #expect(succeeded.serverName == fixture.serverRecord.name)
        #expect(succeeded.jobName == fixture.job.name)
    }

    @Test("The job log comes in pages, and can keep to one job or one server")
    func pagesAndFilters() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        let other = try await fixture.addJob(named: "Other")
        _ = try await fixture.run()
        _ = try await fixture.runNow(other)
        await fixture.runs.waitUntilIdle()
        _ = try await fixture.run()

        // Act
        let first = try await fixture.jobLog("?limit=2")
        let second = try await fixture.jobLog("?limit=2&before=\(try #require(first.nextBefore))")
        let oneJob = try await fixture.jobLog("?job=\(other.id)")
        let oneServer = try await fixture.jobLog("?server=\(fixture.serverRecord.id)")
        let otherServer = try await fixture.jobLog("?server=\(UUID())")
        let unreadable = try await fixture.api.send(.get, HiveEndpoint.jobLog + "?job=not-an-id")

        // Assert
        #expect(first.runs.map(\.jobName) == [fixture.job.name, "Other"])
        #expect(second.runs.map(\.jobName) == [fixture.job.name])
        #expect(second.nextBefore == nil)
        #expect(oneJob.runs.map(\.jobName) == ["Other"])
        #expect(oneServer.runs.count == 3)
        #expect(otherServer.runs.isEmpty)
        #expect(unreadable.status == .badRequest)
    }

    @Test("A job's entries outlive it, with the names it had")
    func outlivesTheJob() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        _ = try await fixture.run()

        // Act
        let removed = try await fixture.api.send(.delete, HiveEndpoint.job(fixture.job.id))
        let page = try await fixture.jobLog()

        // Assert
        #expect(removed.status == .noContent)
        #expect(page.runs.map(\.jobName) == [fixture.job.name])
    }

    @Test("Each step of a run is told to listeners as it happens")
    func events() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        let events = fixture.runs.events.listen()

        // Act
        _ = try await fixture.run()

        // Assert
        var seen: [String] = []
        for await event in events {
            switch event {
            case .queued(_, let trigger): seen.append("queued \(trigger.rawValue)")
            case .started: seen.append("started")
            case .step(_, let step): seen.append("\(step)")
            case .progress(let entry): seen.append("progress \(entry.run.directories.count) \(entry.run.databases.count)")
            case .finished(let entry): seen.append("finished \(entry.run.failure == nil)")
            case .leftQueue: seen.append("left queue")
            }
            if seen.last?.hasPrefix("finished") == true { break }
        }
        #expect(seen == [
            "queued runNow",
            "started",
            "checkingDirectories",
            "pulling(folder: \"site\")",
            "progress 1 0",
            "dumping(database: \"site\")",
            "progress 1 1",
            "completing",
            "finished true",
        ])
    }
}
