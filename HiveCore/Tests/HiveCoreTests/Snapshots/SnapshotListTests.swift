import Darwin
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct SnapshotListTests {
    private func list(_ fixture: BackupRunFixture, job: UUID? = nil) async throws -> APIAnswer {
        try await fixture.api.send(.get, HiveEndpoint.snapshots(ofJob: job ?? fixture.job.id))
    }

    @Test("A job's snapshots are listed newest first, as they are on the drive, with what removing each frees and where they are")
    func matchesTheDrive() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        let made = try await fixture.runDaysApart([1, 1, 1])

        // Act
        let listed = try await list(fixture).decoded(as: JobSnapshots.self)

        // Assert
        let newestFirst = Array(made.reversed())
        #expect(listed.snapshots.map(\.id) == newestFirst.map(\.id))
        #expect(listed.snapshots.map(\.date) == newestFirst.map(\.date))
        #expect(listed.snapshots.map(\.state) == [.complete, .complete, .complete])
        #expect(listed.snapshots.map(\.freesBytes) == newestFirst.map(\.freesBytes))
        #expect(listed.usedBytes == (try fixture.usedBytes()))
        let folder = try #require(listed.folderPath)
        #expect(folder == (try fixture.jobFolder().fileSystemPath))
        let onDrive = try FileManager.default.contentsOfDirectory(atPath: folder).filter { !$0.hasPrefix(".") }
        #expect(onDrive.sorted() == listed.snapshots.map(\.folder).sorted())
    }

    @Test("A snapshot a failed run left is listed as partial, dated when it started")
    func partial() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("can't be read", to: "srv/site/locked.jpg")
        chmod(fixture.source("srv/site/locked.jpg").fileSystemPath, 0)
        defer { chmod(fixture.source("srv/site/locked.jpg").fileSystemPath, 0o644) }
        let failed = try await fixture.run()

        // Act
        let listed = try await list(fixture).decoded(as: JobSnapshots.self)

        // Assert
        #expect(failed.failure == .someFilesNotTransferred)
        #expect(listed.snapshots.map(\.state) == [.partial])
        #expect(listed.snapshots.map(\.date) == [failed.startedAt])
    }

    @Test("While the drive isn't mounted, the snapshots are still listed, without a folder to show")
    func driveMissing() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try await fixture.runDaysApart([1])
        fixture.ejectDrive()

        // Act
        let listed = try await list(fixture).decoded(as: JobSnapshots.self)

        // Assert
        #expect(listed.snapshots.count == 1)
        #expect(listed.folderPath == nil)
    }

    @Test("Only the chosen drive's snapshots are listed")
    func chosenDriveOnly() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try await fixture.runDaysApart([1])
        let other = fixture.temporary.url.appending(path: "Other", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let otherUUID = UUID()
        fixture.api.volumes.set([
            BackupRunFixture.volume(at: fixture.volume),
            BackupRunFixture.volume(at: other, uuid: otherUUID),
        ])
        let chosen = try await fixture.api.send(.put, HiveEndpoint.backupDrive, json: BackupDriveChoice(volumeUUID: otherUUID))

        // Act
        let listed = try await list(fixture).decoded(as: JobSnapshots.self)

        // Assert
        #expect(chosen.status == .ok)
        #expect(listed.snapshots.isEmpty)
        #expect(listed.folderPath == nil)
    }

    @Test("An unknown job is not found")
    func unknownJob() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()

        // Act
        let answer = try await list(fixture, job: UUID())

        // Assert
        #expect(answer.status == .notFound)
    }

    @Test("Snapshots can't be listed without signing in")
    func refusedWithoutSigningIn() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        let path = HiveEndpoint.snapshots(ofJob: fixture.job.id)

        // Act
        let status = try await fixture.api.application.test(.router) { client in
            try await client.execute(uri: path, method: .get) { $0.status }
        }

        // Assert
        #expect(status == .unauthorized)
    }
}
