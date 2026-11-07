import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct BackupRunRoutesTests {
    @Test("Starting a run is recorded in the audit log with the device that started it")
    func audited() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")

        // Act
        _ = try await fixture.run()

        // Assert
        let entry = try #require(try fixture.api.auditLog.page(before: nil, limit: 1).entries.first)
        #expect(entry.event == .backupRunStarted(jobID: fixture.job.id, serverName: fixture.serverRecord.name, jobName: fixture.job.name))
        #expect(entry.deviceID == fixture.api.signIn.device.id)
    }

    @Test("Runs go one at a time: a second is refused while the first is going")
    func oneAtATime() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        let first = try await fixture.api.send(.post, HiveEndpoint.run(ofJob: fixture.job.id))

        // Act
        let second = try await fixture.api.send(.post, HiveEndpoint.run(ofJob: fixture.job.id))
        await fixture.api.api.runs.waitUntilIdle()
        let third = try await fixture.api.send(.post, HiveEndpoint.run(ofJob: fixture.job.id))
        await fixture.api.api.runs.waitUntilIdle()

        // Assert
        #expect(first.status == .accepted)
        #expect(second.status == .conflict)
        #expect(third.status == .accepted)
    }

    @Test("An unknown job is not found, and has no run")
    func unknownJob() async throws {
        // Arrange
        let fixture = try APIFixture()
        let before = try fixture.auditEvents()

        // Act
        let started = try await fixture.send(.post, HiveEndpoint.run(ofJob: UUID()))
        let latest = try await fixture.send(.get, HiveEndpoint.run(ofJob: UUID()))

        // Assert
        #expect(started.status == .notFound)
        #expect(latest.status == .notFound)
        #expect(try fixture.auditEvents() == before)
    }

    @Test("A run can't be started without signing in")
    func refusedWithoutSigningIn() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        let before = try fixture.api.auditEvents()
        let path = HiveEndpoint.run(ofJob: fixture.job.id)

        // Act
        try await fixture.api.application.test(.router) { client in
            try await client.execute(uri: path, method: .post) { response in
                // Assert
                #expect(response.status == .unauthorized)
            }
        }
        await fixture.api.api.runs.waitUntilIdle()

        // Assert
        let status = try await fixture.api.send(.get, HiveEndpoint.run(ofJob: fixture.job.id)).decoded(as: JobStatus.self)
        #expect(status.state == .idle)
        #expect(status.lastRun == nil)
        #expect(try fixture.api.auditEvents() == before)
        #expect(try fixture.catalog().isEmpty)
    }
}
