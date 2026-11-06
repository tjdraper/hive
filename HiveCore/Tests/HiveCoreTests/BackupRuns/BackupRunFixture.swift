import Darwin
import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird

/// The rsync Hive bundles, built by `Scripts/build-rsync.sh`, which `Scripts/build-and-test.sh` runs first.
enum TestRsync {
    static let url: URL = {
        var folder = URL(filePath: #filePath).deletingLastPathComponent()
        while folder.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: folder.appending(path: "Scripts/build-rsync.sh").path) {
                return folder.appending(path: "build/rsync/rsync", directoryHint: .notDirectory)
            }
            folder = folder.deletingLastPathComponent()
        }
        return URL(filePath: "/nonexistent/rsync")
    }()
}

/// An API fixture with a backup drive, and a server whose directories are folders on this Mac.
struct BackupRunFixture {
    static let volumeUUID = UUID()

    let api: APIFixture
    let temporary: TemporaryDirectory
    /// Stands in for the drive's mount point.
    let volume: URL
    /// Stands in for the server's file system.
    let server: URL
    let serverRecord: Server
    let job: BackupJob

    /// `directories` maps each folder within the snapshot to a folder under `server`, made empty.
    init(directories: [(folder: String, source: String)] = [("site", "srv/site")], chooseDrive: Bool = true) async throws {
        api = try APIFixture()
        temporary = try TemporaryDirectory()
        volume = temporary.url.appending(path: "Volume", directoryHint: .isDirectory)
        server = temporary.url.appending(path: "Server", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: volume, withIntermediateDirectories: true)
        for directory in directories {
            try FileManager.default.createDirectory(at: server.appending(path: directory.source), withIntermediateDirectories: true)
        }

        serverRecord = try await api.addServer()
        try await api.confirmHostKey(of: serverRecord)
        let server = server
        var draft = ConfigurationSamples.job(password: nil)
        draft.databases = []
        draft.directories = directories.map {
            BackupDirectory(path: server.appending(path: $0.source).fileSystemPath, folder: $0.folder)
        }
        job = try await api.addJob(draft, to: serverRecord)

        mountDrive()
        if chooseDrive {
            let answer = try await api.send(.put, HiveEndpoint.backupDrive, json: BackupDriveChoice(volumeUUID: Self.volumeUUID))
            guard answer.status == .ok else { throw APIFixtureError.unexpectedStatus(answer.status) }
        }
    }

    var hiveFolder: URL {
        volume.appending(path: "Hive", directoryHint: .isDirectory)
    }

    func mountDrive(caseSensitive: Bool = true, startupDisk: Bool = false) {
        api.volumes.set([Self.volume(at: volume, caseSensitive: caseSensitive, startupDisk: startupDisk)])
    }

    func ejectDrive() {
        api.volumes.set([])
    }

    static func volume(at url: URL, uuid: UUID = volumeUUID, caseSensitive: Bool = true, startupDisk: Bool = false) -> MountedVolume {
        MountedVolume(
            url: url,
            uuid: uuid,
            name: "Test Drive",
            fileSystemType: "apfs",
            formatDescription: caseSensitive ? "APFS (Case-sensitive)" : "APFS",
            isCaseSensitive: caseSensitive,
            isReadOnly: false,
            isLocal: true,
            isStartupDisk: startupDisk,
            totalBytes: 1_000_000_000,
            availableBytes: 500_000_000
        )
    }

    /// The source folder for `relative`, under the stand-in server.
    func source(_ relative: String) -> URL {
        server.appending(path: relative)
    }

    func write(_ text: String, to relative: String) throws {
        let url = source(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// Starts a run through the API a minute after the last, and waits for it to finish.
    func run() async throws -> BackupRun {
        api.signIn.clock.advance(by: 60)
        let started = try await api.send(.post, HiveEndpoint.run(ofJob: job.id))
        guard started.status == .accepted else { throw APIFixtureError.unexpectedStatus(started.status) }
        await api.api.runs.waitUntilIdle()
        return try await api.send(.get, HiveEndpoint.run(ofJob: job.id)).decoded(as: BackupRun.self)
    }

    func catalog() throws -> [SnapshotRecord] {
        try api.signIn.database.writer.read { try SnapshotRecord.order(Column("startedAt")).fetchAll($0) }
    }

    /// The job's complete snapshots on the drive, oldest first.
    func snapshots() throws -> [URL] {
        try catalog().filter { $0.state == .complete }.map { snapshotURL($0) }
    }

    func snapshotURL(_ record: SnapshotRecord) -> URL {
        hiveFolder.appending(path: "\(record.serverFolder)/\(record.jobFolder)/\(record.folder)", directoryHint: .isDirectory)
    }

    /// Everything under `folder`, as paths relative to it.
    static func contents(of folder: URL) -> [String] {
        (FileManager.default.subpaths(atPath: folder.fileSystemPath) ?? []).sorted()
    }
}

func inode(of url: URL) throws -> UInt64 {
    var info = stat()
    guard lstat(url.fileSystemPath, &info) == 0 else { throw POSIXError(.ENOENT) }
    return info.st_ino
}

/// rsync's `--fake-super` attribute, which macOS names without Linux's `user.` prefix.
let fakeSuperAttribute = "rsync.%stat"

func extendedAttribute(_ name: String, of url: URL) -> String? {
    let path = url.fileSystemPath
    let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
    guard size >= 0 else { return nil }
    var buffer = [UInt8](repeating: 0, count: size)
    guard getxattr(path, name, &buffer, size, 0, XATTR_NOFOLLOW) == size else { return nil }
    return String(bytes: buffer, encoding: .utf8)
}

func setExtendedAttribute(_ name: String, to value: String, of url: URL) throws {
    let bytes = Array(value.utf8)
    guard setxattr(url.fileSystemPath, name, bytes, bytes.count, 0, XATTR_NOFOLLOW) == 0 else { throw POSIXError(.EIO) }
}
