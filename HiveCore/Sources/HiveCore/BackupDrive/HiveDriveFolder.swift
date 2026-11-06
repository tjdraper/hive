import Darwin
import Foundation
import HiveKit

/// The `Hive` folder at the top of the backup drive, holding a marker with the Hive ID so a drive from
/// another Hive is never written to by mistake.
enum HiveDriveFolder {
    static let name = "Hive"
    static let markerName = ".hive-drive.json"
    /// Far more than a marker needs, so a stray large file is never read whole.
    private static let largestMarker = 4096

    struct Marker: Codable, Equatable {
        static let currentFormat = 1

        let format: Int
        let hiveID: UUID
    }

    enum Mark: Equatable {
        case thisHive
        case anotherHive
        /// No `Hive` folder, or an empty one: Hive can claim it.
        case unclaimed
        /// A `Hive` folder with no marker that already holds something, or one that isn't a real folder.
        case inUse
        /// Hive can't look, which can mean it lacks Full Disk Access.
        case unreadable
    }

    static func url(on volume: URL) -> URL {
        volume.appending(path: name, directoryHint: .isDirectory)
    }

    /// Reads without writing anything.
    static func mark(on volume: URL, hiveID: UUID) -> Mark {
        let folder = url(on: volume)
        var info = stat()
        guard lstat(folder.fileSystemPath, &info) == 0 else { return errno == ENOENT ? .unclaimed : .unreadable }
        guard info.st_mode & S_IFMT == S_IFDIR else { return .inUse }

        if let marker = readMarker(in: folder) {
            return marker.hiveID == hiveID ? .thisHive : .anotherHive
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.fileSystemPath) else { return .unreadable }
        return contents.isEmpty ? .unclaimed : .inUse
    }

    /// Makes the folder and its marker. Returns the problem when it's another Hive's, in use, or can't be written.
    static func claim(on volume: URL, hiveID: UUID) -> BackupDriveProblem? {
        switch mark(on: volume, hiveID: hiveID) {
        case .thisHive: return nil
        case .anotherHive: return .belongsToAnotherHive
        case .inUse: return .folderInUse
        case .unreadable: return .notWritable
        case .unclaimed: break
        }

        let folder = url(on: volume)
        guard mkdir(folder.fileSystemPath, 0o755) == 0 || errno == EEXIST else { return .notWritable }
        do {
            let data = try JSONEncoder().encode(Marker(format: Marker.currentFormat, hiveID: hiveID))
            try data.write(to: folder.appending(path: markerName, directoryHint: .notDirectory), options: .withoutOverwriting)
        } catch {
            return .notWritable
        }
        return mark(on: volume, hiveID: hiveID) == .thisHive ? nil : .notWritable
    }

    private static func readMarker(in folder: URL) -> Marker? {
        let path = folder.appending(path: markerName, directoryHint: .notDirectory).fileSystemPath
        // O_NOFOLLOW, so a link can't stand in for the marker.
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard let data = try? handle.read(upToCount: largestMarker) else { return nil }
        return try? JSONDecoder().decode(Marker.self, from: data)
    }
}
