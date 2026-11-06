import Darwin
import Foundation
import HiveKit

/// A volume mounted on the Hive Mac, as Hive needs to know it.
struct MountedVolume: Sendable, Equatable {
    let url: URL
    let uuid: UUID
    let name: String
    /// As `statfs` names it, such as `apfs`.
    let fileSystemType: String
    let formatDescription: String
    let isCaseSensitive: Bool
    let isReadOnly: Bool
    let isLocal: Bool
    let isStartupDisk: Bool
    let totalBytes: Int64
    let availableBytes: Int64

    /// Why Hive can't keep snapshots on it, whatever is on it.
    var unsuitability: BackupDriveProblem? {
        if isStartupDisk { return .startupDisk }
        if !isLocal { return .notLocal }
        if fileSystemType != "apfs" { return .notAPFS }
        if !isCaseSensitive { return .notCaseSensitive }
        if isReadOnly { return .readOnly }
        return nil
    }
}

/// Lists the Mac's mounted volumes. Tests stand in for it with folders of their own.
protocol VolumeListing: Sendable {
    func mountedVolumes() -> [MountedVolume]
}

struct MountedVolumeList: VolumeListing {
    private static let keys: [URLResourceKey] = [
        .volumeNameKey,
        .volumeUUIDStringKey,
        .volumeLocalizedFormatDescriptionKey,
        .volumeIsReadOnlyKey,
        .volumeIsLocalKey,
        .volumeIsRootFileSystemKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
    ]

    func mountedVolumes() -> [MountedVolume] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Self.keys, options: [.skipHiddenVolumes])
        return (urls ?? []).compactMap(Self.volume(at:))
    }

    /// Nil for a volume without a UUID, which Hive couldn't find again.
    private static func volume(at url: URL) -> MountedVolume? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)),
              let uuid = values.volumeUUIDString.flatMap(UUID.init(uuidString:))
        else { return nil }
        let path = url.fileSystemPath
        return MountedVolume(
            url: url,
            uuid: uuid,
            name: values.volumeName ?? url.lastPathComponent,
            fileSystemType: fileSystemType(at: path) ?? "",
            formatDescription: values.volumeLocalizedFormatDescription ?? "",
            // The format's own answer, rather than the resource value, which describes what the format could support.
            isCaseSensitive: pathconf(path, _PC_CASE_SENSITIVE) == 1,
            isReadOnly: values.volumeIsReadOnly ?? true,
            isLocal: values.volumeIsLocal ?? false,
            isStartupDisk: values.volumeIsRootFileSystem ?? false,
            totalBytes: Int64(values.volumeTotalCapacity ?? 0),
            availableBytes: Int64(values.volumeAvailableCapacity ?? 0)
        )
    }

    private static func fileSystemType(at path: String) -> String? {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        return withUnsafeBytes(of: info.f_fstypename) { bytes in
            String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8)
        }
    }
}
