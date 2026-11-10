import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct StandingAlertTests {
    private static let day: TimeInterval = 24 * 60 * 60

    @Test("An overdue job emails once, then daily, until it completes a snapshot")
    func overdue() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        try await fixture.succeedingRun()

        // Act
        fixture.clock.advance(by: Self.day)
        await fixture.check()
        await fixture.check()
        fixture.clock.advance(by: Self.day)
        await fixture.check()
        try await fixture.succeedingRun()
        await fixture.check()
        let openAfterSnapshot = try fixture.store.all()

        // Assert
        #expect(try fixture.sent().map(\.subject) == [
            "Backup overdue: “Main site” on “Studio Web”",
            "Still overdue: “Main site” on “Studio Web”",
        ])
        #expect(openAfterSnapshot.isEmpty)
    }

    @Test("A job whose runs fail isn't also emailed about as overdue")
    func failingJobNotOverdue() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        try await fixture.failingRun()

        // Act
        fixture.clock.advance(by: 3 * Self.day)
        await fixture.check()

        // Assert
        #expect(try fixture.sent(startingWith: "Backup overdue").isEmpty)
    }

    @Test("A job waiting in the queue isn't overdue yet")
    func waitingJobNotOverdue() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        try await fixture.succeedingRun()
        fixture.clock.advance(by: Self.day)
        let queue = BackupQueue(database: fixture.api.signIn.database)
        _ = try queue.add(jobID: fixture.runs.job.id, trigger: .scheduled, at: fixture.clock.now)

        // Act
        await fixture.api.api.alerts.check()

        // Assert
        #expect(try fixture.store.all().isEmpty)
    }

    @Test("A server over its quota emails once, and again only after it has fitted in between")
    func overQuota() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        let retention = RetentionStore(database: fixture.api.signIn.database)
        let serverID = fixture.runs.serverRecord.id

        // Act
        try retention.markOverQuota(serverID: serverID, at: fixture.clock.now)
        await fixture.check()
        fixture.clock.advance(by: Self.day)
        await fixture.check()
        try retention.clearOverQuota(serverID: serverID)
        await fixture.check()
        try retention.markOverQuota(serverID: serverID, at: fixture.clock.now)
        await fixture.check()

        // Assert
        #expect(try fixture.sent(startingWith: "Over quota").map(\.subject) == ["Over quota: “Studio Web”", "Over quota: “Studio Web”"])
    }

    @Test("A drive filling up emails once, keeps quiet hovering near the line, and again only after it had room")
    func driveFillingUp() async throws {
        // Arrange
        let fixture = try await AlertFixture()

        // Act
        for available: Int64 in [50_000_000, 120_000_000, 50_000_000, 120_000_000, 200_000_000, 50_000_000] {
            fixture.api.volumes.set([Self.volume(fixture, availableBytes: available)])
            await fixture.check()
        }

        // Assert
        #expect(try fixture.sent(startingWith: "The backup drive is filling up").count == 2)
    }

    @Test("Quotas adding up to more than the drive holds email once, until they fit")
    func quotasExceedDrive() async throws {
        // Arrange
        let fixture = try await AlertFixture()

        // Act
        try fixture.setQuota(2_000_000_000)
        await fixture.check()
        fixture.clock.advance(by: Self.day)
        await fixture.check()
        try fixture.setQuota(500_000_000)
        await fixture.check()
        let openAfterFitting = try fixture.store.all()

        // Assert
        let sent = try fixture.sent(startingWith: "Quotas")
        #expect(sent.map(\.subject) == ["Quotas add up to more than the backup drive holds"])
        #expect(sent.first?.body.contains("2 GB") == true)
        #expect(!openAfterFitting.contains { $0.facts == .quotasExceedDrive })
    }

    @Test("A snapshot much smaller than the one before emails once, naming the folder")
    func snapshotShrank() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        try fixture.runs.write(String(repeating: "x", count: 3_000_000), to: "srv/site/big.bin")
        _ = try await fixture.runs.runEntry(after: 60)
        _ = try await fixture.runs.runEntry(after: 60)
        await fixture.check()
        let similar = try fixture.sent()

        // Act
        try FileManager.default.removeItem(at: fixture.runs.source("srv/site/big.bin"))
        _ = try await fixture.runs.runEntry(after: 60)
        await fixture.check()
        await fixture.check()

        // Assert
        #expect(similar.isEmpty)
        let sent = try fixture.sent()
        #expect(sent.map(\.subject) == ["Snapshot much smaller: “Main site” on “Studio Web”"])
        #expect(sent.first?.body.contains("Folder “site”") == true)
        #expect(try fixture.store.all().isEmpty)
    }

    private static func volume(_ fixture: AlertFixture, availableBytes: Int64) -> MountedVolume {
        let full = BackupRunFixture.volume(at: fixture.runs.volume)
        return MountedVolume(
            url: full.url,
            uuid: full.uuid,
            name: full.name,
            fileSystemType: full.fileSystemType,
            formatDescription: full.formatDescription,
            isCaseSensitive: full.isCaseSensitive,
            isReadOnly: full.isReadOnly,
            isLocal: full.isLocal,
            isStartupDisk: full.isStartupDisk,
            totalBytes: full.totalBytes,
            availableBytes: availableBytes
        )
    }
}
