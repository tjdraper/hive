import Darwin
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

struct SnapshotFolderTests {
    @Test(
        "A server's or job's name can't place its folder anywhere but where it belongs",
        arguments: ["../../etc", "/etc/passwd", ".hidden", "..", ".", "a/b", "tab\there", "", "   "]
    )
    func namesStayInPlace(name: String) {
        // Act
        let candidates = SnapshotFolderName.candidates(name: name, id: UUID())

        // Assert
        for candidate in candidates {
            #expect(!candidate.contains("/"))
            #expect(!candidate.hasPrefix("."))
            #expect(!TextCheck.hasControlCharacters(candidate))
            #expect(!candidate.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @Test("A folder is named from the name and a short form of the ID, with the full ID as the fallback")
    func namedFromNameAndID() throws {
        // Arrange
        let id = try #require(UUID(uuidString: "3F2A9C1B-0000-4000-8000-00000000ABCD"))

        // Act
        let candidates = SnapshotFolderName.candidates(name: "Studio Web: main", id: id)

        // Assert
        #expect(candidates == ["Studio Web- main 3f2a9c1b", "Studio Web- main 3f2a9c1b00004000800000000000abcd"])
    }

    @Test("Snapshots are named for when they completed, in UTC and without colons")
    func snapshotName() {
        // Act
        let name = SnapshotFolderName.snapshot(at: Date(timeIntervalSince1970: 1_800_000_000))

        // Assert
        #expect(name == "2027-01-15T080000Z")
        #expect(SnapshotFolderName.partial(at: Date(timeIntervalSince1970: 1_800_000_000)) == "2027-01-15T080000Z.partial")
    }

    @Test("A folder is never made through a symbolic link or a name that leaves its parent")
    func realFoldersOnly() throws {
        // Arrange
        let temporary = try TemporaryDirectory()
        let outside = temporary.url.appending(path: "Outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let base = temporary.url.appending(path: "Snapshot", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: base.appending(path: "files"), withDestinationURL: outside)

        // Act, Assert
        #expect(throws: RealFolderError.notARealFolder) { try RealFolder.make(["files", "site"], under: base) }
        #expect(throws: RealFolderError.invalidName) { try RealFolder.make(["..", "escaped"], under: base) }
        #expect(throws: RealFolderError.invalidName) { try RealFolder.make(["a/b"], under: base) }
        #expect(RealFolder.existing(["files"], under: base) == nil)
        #expect(BackupRunFixture.contents(of: outside).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: temporary.url.appending(path: "escaped").fileSystemPath))
    }

    @Test("A partial snapshot with a link where a folder must go is left alone, and nothing is written through the link")
    func linkInPartial() async throws {
        // Arrange
        let fixture = try await BackupRunFixture(directories: [("images/galleries", "srv/galleries"), ("site", "srv/site")])
        try fixture.write("a gallery", to: "srv/galleries/summer.jpg")
        try fixture.write("can't be read yet", to: "srv/site/locked.txt")
        chmod(fixture.source("srv/site/locked.txt").fileSystemPath, 0)
        _ = try await fixture.run()
        let partial = try #require(try fixture.catalog().first)
        let outside = fixture.temporary.url.appending(path: "Outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let images = fixture.snapshotURL(partial).appending(path: "files/images")
        try FileManager.default.removeItem(at: images)
        try FileManager.default.createSymbolicLink(at: images, withDestinationURL: outside)
        chmod(fixture.source("srv/site/locked.txt").fileSystemPath, 0o644)

        // Act
        let run = try await fixture.run()

        // Assert
        #expect(run.failure == nil)
        #expect(BackupRunFixture.contents(of: outside).isEmpty)
        let catalog = try fixture.catalog()
        #expect(catalog.map(\.state) == [.partial, .complete])
        #expect(catalog.first?.id == partial.id)
        let snapshot = try #require(try fixture.snapshots().first)
        #expect(BackupRunFixture.contents(of: snapshot.appending(path: "files/images")) == ["galleries", "galleries/summer.jpg"])
    }

    @Test("Two similar job names, a rename, and a job added again under an old name never share a folder")
    func jobsNeverShare() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        let resolver = SnapshotFolderResolver(database: fixture.api.signIn.database)
        func folders(_ job: BackupJob) throws -> SnapshotFolders {
            try resolver.folders(
                serverID: fixture.serverRecord.id,
                serverName: fixture.serverRecord.name,
                jobID: job.id,
                jobName: job.name,
                in: fixture.hiveFolder
            )
        }
        var draft = fixture.job.draft
        draft.name = "Main/site"
        let similar = try await fixture.api.addJob(draft, to: fixture.serverRecord)
        draft.name = "Main:site"
        let alsoSimilar = try await fixture.api.addJob(draft, to: fixture.serverRecord)
        let original = try folders(fixture.job)
        _ = try await fixture.run()

        // Act
        draft.name = "Renamed"
        _ = try await fixture.api.send(.put, HiveEndpoint.job(fixture.job.id), json: draft)
        let afterRename = try folders(fixture.job)
        _ = try await fixture.api.send(.delete, HiveEndpoint.job(fixture.job.id))
        draft.name = fixture.job.name
        let readded = try await fixture.api.addJob(draft, to: fixture.serverRecord)

        // Assert
        let similarFolders = try [folders(similar).job, folders(alsoSimilar).job]
        #expect(Set(similarFolders + [original.job]).count == 3)
        #expect(afterRename == original)
        #expect(try folders(readded).job != original.job)
        #expect(try folders(readded).server == original.server)
    }

    @Test("Removing a job or its server keeps its snapshots in the catalog and on the drive")
    func removalKeepsSnapshots() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        try fixture.write("hello", to: "srv/site/index.html")
        _ = try await fixture.run()
        let before = try fixture.catalog()

        // Act
        _ = try await fixture.api.send(.delete, HiveEndpoint.server(fixture.serverRecord.id))

        // Assert
        #expect(try fixture.api.jobs.job(id: fixture.job.id) == nil)
        #expect(try fixture.catalog() == before)
        let file = fixture.snapshotURL(before[0]).appending(path: "files/site/index.html")
        #expect(FileManager.default.fileExists(atPath: file.fileSystemPath))
    }
}
