import Foundation
@testable import HiveCore
import HiveKit
import Testing

/// Runs that fail before writing anything: the drive or the server's directories aren't as they should be.
struct RunRefusalTests {
    /// Everything on the stand-in drive, and every snapshot Hive knows of, before and after a run.
    private func expectNothingWritten(by run: BackupRun, as failure: BackupFailure, fixture: BackupRunFixture, before: [String]) throws {
        #expect(run.failure == failure)
        #expect(run.directories.isEmpty)
        #expect(BackupRunFixture.contents(of: fixture.volume) == before)
        #expect(try fixture.catalog().isEmpty)
    }

    @Test("A missing drive fails the run without creating anything")
    func missingDrive() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        let before = BackupRunFixture.contents(of: fixture.volume)
        fixture.ejectDrive()

        // Act
        let run = try await fixture.run()

        // Assert
        try expectNothingWritten(by: run, as: .driveMissing, fixture: fixture, before: before)
    }

    @Test("A drive marked as another Hive's fails the run without creating anything")
    func mismatchedMarker() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        let marker = HiveDriveFolder.Marker(format: HiveDriveFolder.Marker.currentFormat, hiveID: UUID())
        try JSONEncoder().encode(marker).write(to: fixture.hiveFolder.appending(path: HiveDriveFolder.markerName))
        let before = BackupRunFixture.contents(of: fixture.volume)

        // Act
        let run = try await fixture.run()

        // Assert
        try expectNothingWritten(by: run, as: .driveNotThisHives, fixture: fixture, before: before)
    }

    @Test("A drive whose marker is gone fails the run without creating anything")
    func missingMarker() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        try FileManager.default.removeItem(at: fixture.hiveFolder.appending(path: HiveDriveFolder.markerName))
        let before = BackupRunFixture.contents(of: fixture.volume)

        // Act
        let run = try await fixture.run()

        // Assert
        try expectNothingWritten(by: run, as: .driveNotThisHives, fixture: fixture, before: before)
    }

    @Test("Without a chosen drive, the run fails without creating anything")
    func noDrive() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(chooseDrive: false)
        try fixture.write("hello", to: "srv/site/index.html")

        // Act
        let run = try await fixture.run()

        // Assert
        try expectNothingWritten(by: run, as: .driveNotChosen, fixture: fixture, before: [])
    }

    @Test("A missing source folder fails the run without creating anything")
    func missingSource() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(directories: [("site", "srv/site"), ("uploads", "srv/uploads")])
        try fixture.write("hello", to: "srv/site/index.html")
        try FileManager.default.removeItem(at: fixture.source("srv/uploads"))
        let before = BackupRunFixture.contents(of: fixture.volume)

        // Act
        let run = try await fixture.run()

        // Assert
        try expectNothingWritten(by: run, as: .sourceMissing, fixture: fixture, before: before)
    }

    @Test("A source that's a file rather than a folder fails the run without creating anything")
    func sourceIsFile() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try FileManager.default.removeItem(at: fixture.source("srv/site"))
        try fixture.write("not a folder", to: "srv/site")
        let before = BackupRunFixture.contents(of: fixture.volume)

        // Act
        let run = try await fixture.run()

        // Assert
        try expectNothingWritten(by: run, as: .sourceMissing, fixture: fixture, before: before)
    }

    @Test("An empty source folder fails the run without creating anything")
    func emptySource() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(directories: [("site", "srv/site"), ("uploads", "srv/uploads")])
        try fixture.write("hello", to: "srv/site/index.html")
        let before = BackupRunFixture.contents(of: fixture.volume)

        // Act
        let run = try await fixture.run()

        // Assert
        try expectNothingWritten(by: run, as: .sourceEmpty, fixture: fixture, before: before)
    }
}
