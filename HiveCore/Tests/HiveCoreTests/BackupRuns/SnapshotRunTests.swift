import Darwin
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

/// Runs the bundled rsync between temporary folders. No `ssh`, and no server.
struct SnapshotRunTests {
    @Test("A run makes a complete snapshot with the job's files and a manifest, and leaves no partial folder")
    func firstRun() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        try fixture.write("a photo", to: "srv/site/uploads/photo.jpg")

        // Act
        let run = try await fixture.run()

        // Assert
        #expect(run.failure == nil)
        #expect(run.directories.map(\.folder) == ["site"])
        #expect(run.directories.first?.filesTransferred == 2)
        let snapshot = try #require(try fixture.snapshots().first)
        #expect(BackupRunFixture.contents(of: snapshot.appending(path: "files/site")) == ["index.html", "uploads", "uploads/photo.jpg"])
        #expect(try String(contentsOf: snapshot.appending(path: "files/site/index.html"), encoding: .utf8) == "hello")

        let manifest = try SnapshotManifest.decoded(from: Data(contentsOf: snapshot.appending(path: SnapshotManifest.fileName)))
        #expect(manifest.complete)
        #expect(manifest.hiveID == fixture.api.signIn.hiveID)
        #expect(manifest.server.id == fixture.serverRecord.id)
        #expect(manifest.job.id == fixture.job.id)
        #expect(manifest.directories.map(\.folder) == ["site"])

        let jobFolder = snapshot.deletingLastPathComponent()
        #expect(BackupRunFixture.contents(of: jobFolder).filter { !$0.contains("/") } == [snapshot.lastPathComponent])
        #expect(!snapshot.lastPathComponent.hasSuffix(SnapshotFolderName.partialSuffix))
    }

    @Test("In a second snapshot, an unchanged file is a hard link to the first's, a changed one isn't, and a deleted one is gone")
    func secondRunLinks() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("unchanged", to: "srv/site/unchanged.txt")
        try fixture.write("before", to: "srv/site/changed.txt")
        try fixture.write("going", to: "srv/site/deleted.txt")
        _ = try await fixture.run()
        try fixture.write("after, and longer", to: "srv/site/changed.txt")
        try FileManager.default.removeItem(at: fixture.source("srv/site/deleted.txt"))

        // Act
        let run = try await fixture.run()

        // Assert
        #expect(run.failure == nil)
        #expect(run.directories.first?.filesTransferred == 1)
        let snapshots = try fixture.snapshots()
        try #require(snapshots.count == 2)
        let (first, second) = (snapshots[0].appending(path: "files/site"), snapshots[1].appending(path: "files/site"))
        #expect(try inode(of: first.appending(path: "unchanged.txt")) == inode(of: second.appending(path: "unchanged.txt")))
        #expect(try inode(of: first.appending(path: "changed.txt")) != inode(of: second.appending(path: "changed.txt")))
        #expect(BackupRunFixture.contents(of: second) == ["changed.txt", "unchanged.txt"])
    }

    @Test("A changed file in the new snapshot leaves the old snapshot's copy untouched")
    func oldCopyUntouched() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("the first version", to: "srv/site/notes.txt")
        _ = try await fixture.run()
        try fixture.write("the second version", to: "srv/site/notes.txt")

        // Act
        _ = try await fixture.run()

        // Assert
        let snapshots = try fixture.snapshots()
        try #require(snapshots.count == 2)
        #expect(try String(contentsOf: snapshots[0].appending(path: "files/site/notes.txt"), encoding: .utf8) == "the first version")
        #expect(try String(contentsOf: snapshots[1].appending(path: "files/site/notes.txt"), encoding: .utf8) == "the second version")
    }

    @Test("Owners and groups Hive can't set are kept in an extended attribute, and an unchanged file with one still links")
    func ownersKept() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("owned by www-data", to: "srv/site/owned.txt")
        // A local copy reads owners from the same attribute on the source side, standing in for a
        // server's real owners, which a test can't set without root.
        let owner = "100640 0,0 33:999"
        try setExtendedAttribute(fakeSuperAttribute, to: owner, of: fixture.source("srv/site/owned.txt"))

        // Act
        _ = try await fixture.run()
        _ = try await fixture.run()

        // Assert
        let snapshots = try fixture.snapshots()
        try #require(snapshots.count == 2)
        let (first, second) = (snapshots[0].appending(path: "files/site/owned.txt"), snapshots[1].appending(path: "files/site/owned.txt"))
        #expect(extendedAttribute(fakeSuperAttribute, of: first) == owner)
        #expect(try inode(of: first) == inode(of: second))
    }

    @Test("A run with a partial folder left over picks it up instead of starting again")
    func partialPickedUp() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(directories: [("site", "srv/site"), ("uploads", "srv/uploads")])
        try fixture.write("large and already copied", to: "srv/site/large.bin")
        try fixture.write("can't be read yet", to: "srv/uploads/locked.jpg")
        chmod(fixture.source("srv/uploads/locked.jpg").fileSystemPath, 0)
        let failed = try await fixture.run()
        let partial = try #require(try fixture.catalog().first)
        let partialFolder = try inode(of: fixture.snapshotURL(partial))
        chmod(fixture.source("srv/uploads/locked.jpg").fileSystemPath, 0o644)

        // Act
        let run = try await fixture.run()

        // Assert
        #expect(failed.failure == .someFilesNotTransferred)
        #expect(partial.state == .partial)
        #expect(run.failure == nil)
        #expect(run.directories.map(\.filesTransferred) == [0, 1])
        let catalog = try fixture.catalog()
        #expect(catalog.count == 1)
        #expect(catalog.first?.id == partial.id)
        #expect(catalog.first?.state == .complete)
        let snapshot = try #require(try fixture.snapshots().first)
        #expect(try inode(of: snapshot) == partialFolder)
        let files = BackupRunFixture.contents(of: snapshot.appending(path: "files"))
        #expect(files == ["site", "site/large.bin", "uploads", "uploads/locked.jpg"])
    }

    @Test("A partial from before the job's directories changed isn't picked up, and goes once the new snapshot completes")
    func stalePartialLeft() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(directories: [("site", "srv/site"), ("uploads", "srv/uploads")])
        try fixture.write("hello", to: "srv/site/index.html")
        try fixture.write("can't be read", to: "srv/uploads/locked.jpg")
        chmod(fixture.source("srv/uploads/locked.jpg").fileSystemPath, 0)
        defer { chmod(fixture.source("srv/uploads/locked.jpg").fileSystemPath, 0o644) }
        _ = try await fixture.run()
        let partial = try #require(try fixture.catalog().first)
        var draft = fixture.job.draft
        draft.directories.removeLast()
        _ = try await fixture.api.send(.put, HiveEndpoint.job(fixture.job.id), json: draft)

        // Act
        let run = try await fixture.run()

        // Assert
        #expect(run.failure == nil)
        #expect(try fixture.catalog().map(\.state) == [.complete])
        #expect(!FileManager.default.fileExists(atPath: fixture.snapshotURL(partial).fileSystemPath))
        let snapshot = try #require(try fixture.snapshots().first)
        #expect(BackupRunFixture.contents(of: snapshot.appending(path: "files")) == ["site", "site/index.html"])
    }
}
