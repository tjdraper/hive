import Darwin
import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct DriveAlertTests {
    private static let day: TimeInterval = 24 * 60 * 60

    @Test("A missing drive sends one email for the Hive, however many jobs fail, and none of their own")
    func oneEmailForEveryJob() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        let others = [try await fixture.runs.addJob(named: "blog"), try await fixture.runs.addJob(named: "shop")]
        fixture.runs.ejectDrive()

        // Act
        _ = try await fixture.runs.runEntry(after: 60)
        for job in others {
            _ = try await fixture.runs.runNow(job)
            await fixture.runs.runs.waitUntilIdle()
        }
        await fixture.check()
        _ = try await fixture.runs.runEntry(after: 60)
        await fixture.check()

        // Assert
        let sent = try fixture.sent()
        #expect(sent.filter { $0.subject == "The backup drive is missing" }.count == 1)
        #expect(!sent.contains { $0.subject.hasPrefix("Backup") })
        #expect(try #require(sent.first { $0.subject == "The backup drive is missing" }).body.contains("“Test Drive”"))
    }

    @Test("A drive still missing a day later sends a reminder, and once it's back nothing more is sent")
    func remindsUntilBack() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        fixture.runs.ejectDrive()
        _ = try await fixture.runs.runEntry(after: 60)
        await fixture.check()

        // Act
        fixture.clock.advance(by: Self.day)
        await fixture.check()
        fixture.runs.mountDrive()
        await fixture.check()
        fixture.clock.advance(by: Self.day)
        await fixture.check()

        // Assert
        #expect(try fixture.sent(startingWith: "Still: the backup").count == 1)
        #expect(try fixture.sent(startingWith: "The backup drive is missing").count == 1)
        #expect(try fixture.store.all().allSatisfy { $0.facts != .driveUnavailable(.missing) })
    }

    @Test("A missing drive's alert ends once it's back, whether or not Hive has Full Disk Access")
    func backWithoutFullDiskAccess() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        fixture.api.fullDiskAccess.set(EPERM)
        fixture.runs.ejectDrive()
        _ = try await fixture.runs.runEntry(after: 60)
        await fixture.check()

        // Act
        fixture.runs.mountDrive()
        await fixture.check()

        // Assert
        #expect(try fixture.sent(startingWith: "The backup drive is missing").count == 1)
        #expect(try fixture.store.all().isEmpty)
    }

    @Test("A run that can't write the drive without Full Disk Access says so, once for the Hive, until it's granted again")
    func lostFullDiskAccess() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        fixture.api.fullDiskAccess.set(EPERM)
        let other = try await fixture.runs.addJob(named: "blog")

        // Act
        try fixture.recordRun(failing: .couldNotWriteSnapshot)
        try fixture.recordRun(failing: .couldNotWriteSnapshot, job: other)
        await fixture.check()
        fixture.api.fullDiskAccess.set(0)
        await fixture.check()
        fixture.clock.advance(by: Self.day)
        await fixture.check()

        // Assert
        let sent = try fixture.sent()
        #expect(sent.filter { $0.subject == "Hive has lost Full Disk Access" }.count == 1)
        #expect(!sent.contains { $0.subject.hasPrefix("Backup") || $0.subject.hasPrefix("Still") })
    }

    @Test("Writing the drive failing with Full Disk Access is the job's own failure")
    func couldNotWriteWithAccess() async throws {
        // Arrange
        let fixture = try await AlertFixture()

        // Act
        try fixture.recordRun(failing: .couldNotWriteSnapshot)
        await fixture.check()

        // Assert
        #expect(try fixture.sent(startingWith: "Backup failed").count == 1)
    }
}
