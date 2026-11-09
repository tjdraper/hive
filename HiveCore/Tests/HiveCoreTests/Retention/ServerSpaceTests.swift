import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

struct ServerSpaceTests {
    @Test("A server's space is the sum of its jobs' on the chosen drive, as its quota counts it")
    func sumsJobs() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        let other = try await fixture.addJob(named: "other")
        try await fixture.runDaysApart([1, 1])
        try await fixture.runDaysApart([0], job: other, source: "srv/other")
        let used = try #require(try fixture.usedBytes())
        let otherUsed = try #require(try fixture.usedBytes(of: other))

        // Act
        let answer = try await fixture.api.send(.get, HiveEndpoint.space(ofServer: fixture.serverRecord.id))

        // Assert
        #expect(answer.status == .ok)
        #expect(try answer.decoded(as: ServerSpace.self) == ServerSpace(usedBytes: used + otherUsed))
    }

    @Test("A server whose jobs haven't run yet uses nothing")
    func nothingYet() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()

        // Act
        let answer = try await fixture.api.send(.get, HiveEndpoint.space(ofServer: fixture.serverRecord.id))

        // Assert
        #expect(try answer.decoded(as: ServerSpace.self) == ServerSpace(usedBytes: 0))
    }

    @Test("A server's space is unknown while one of its jobs with snapshots isn't counted")
    func uncountedJob() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try await fixture.runDaysApart([1])
        let jobID = fixture.job.id
        try await fixture.database.writer.write { database in
            try SnapshotSpaceStore.setUsedBytes(nil, ofJob: jobID, onDrive: BackupRunFixture.volumeUUID.uuidString, in: database)
        }

        // Act
        let answer = try await fixture.api.send(.get, HiveEndpoint.space(ofServer: fixture.serverRecord.id))

        // Assert
        #expect(try answer.decoded(as: ServerSpace.self) == ServerSpace(usedBytes: nil))
    }

    @Test("A server that doesn't exist has no space to read")
    func unknownServer() async throws {
        // Arrange
        let fixture = try APIFixture()

        // Act
        let answer = try await fixture.send(.get, HiveEndpoint.space(ofServer: UUID()))

        // Assert
        #expect(answer.status == .notFound)
    }
}
