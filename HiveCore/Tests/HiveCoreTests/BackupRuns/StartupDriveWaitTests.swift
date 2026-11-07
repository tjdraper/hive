import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

/// The fixture's Hive started as it was made, and gives the drive five minutes.
struct StartupDriveWaitTests {
    private static let grace: TimeInterval = 5 * 60

    @Test("Just after Hive starts, a run waits for the backup drive, and goes once it mounts")
    func waitsForTheDrive() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(startupDriveGrace: Self.grace)
        try fixture.write("hello", to: "srv/site/index.html")
        fixture.ejectDrive()
        let (volumes, drive) = (fixture.api.volumes, BackupRunFixture.volume(at: fixture.volume))
        fixture.api.pauses.onEach { count in
            if count == 3 { volumes.set([drive]) }
        }

        // Act
        let entry = try await fixture.runEntry()

        // Assert
        #expect(entry.run.failure == nil)
        #expect(fixture.api.pauses.count == 3)
        #expect(try fixture.snapshots().count == 1)
    }

    @Test("A drive still missing a few minutes after Hive started fails the run")
    func givesUp() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(startupDriveGrace: Self.grace)
        try fixture.write("hello", to: "srv/site/index.html")
        fixture.ejectDrive()

        // Act
        _ = try await fixture.runNow()
        await fixture.runs.waitUntilIdle()

        // Assert
        #expect(try await fixture.status().lastRun?.run.failure == .driveMissing)
        #expect(fixture.api.pauses.count == 30)
        #expect(try fixture.catalog().isEmpty)
    }

    @Test("Once Hive has been running a few minutes, a missing drive fails a run at once")
    func noWaitLater() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(startupDriveGrace: Self.grace)
        try fixture.write("hello", to: "srv/site/index.html")
        fixture.clock.advance(by: Self.grace)
        fixture.ejectDrive()

        // Act
        let run = try await fixture.run()

        // Assert
        #expect(run.failure == .driveMissing)
        #expect(fixture.api.pauses.count < 1)
    }

    @Test("A run waiting for the drive can be cancelled")
    func cancelWhileWaiting() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(startupDriveGrace: 10 * 24 * 60 * 60)
        try fixture.write("hello", to: "srv/site/index.html")
        fixture.ejectDrive()
        fixture.api.pauses.takeRealTime(.milliseconds(5))
        _ = try await fixture.runNow()
        try await fixture.waitUntilRunning(.waitingForDrive)

        // Act
        let cancelled = try await fixture.api.send(.delete, HiveEndpoint.run(ofJob: fixture.job.id))
        await fixture.runs.waitUntilIdle()

        // Assert
        #expect(cancelled.status == .noContent)
        #expect(try await fixture.status().lastRun?.run.failure == .cancelled)
    }
}
