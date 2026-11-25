import Foundation
import ScoutProtocol
import Synchronization

/// Where the backup drive is mounted, for leaving it out of the Hive Mac's disk alerts. Listing the
/// Mac's volumes cost more than the rest of keeping a sample, so it's listed again only when the
/// sample's filesystems or the chosen drive change.
final class BackupDriveMountResolver: Sendable {
    private struct Resolved {
        var volumeUUID: UUID
        /// Each filesystem's device and mount point, so another volume mounted where the drive was
        /// counts as a change.
        var filesystems: [String]
        var mountPoint: String?
    }

    private let volumes: any VolumeListing
    private let resolved = Mutex<Resolved?>(nil)

    init(volumes: any VolumeListing) {
        self.volumes = volumes
    }

    func mountPoint(of volumeUUID: UUID, among filesystems: [FilesystemFigures]) -> String? {
        let mounted = filesystems.map { "\($0.device) \($0.mountPoint)" }.sorted()
        if let resolved = resolved.withLock({ $0 }), resolved.volumeUUID == volumeUUID, resolved.filesystems == mounted {
            return resolved.mountPoint
        }
        let mountPoint = volumes.mountedVolumes().first { $0.uuid == volumeUUID }?.url.fileSystemPath
        resolved.withLock { $0 = Resolved(volumeUUID: volumeUUID, filesystems: mounted, mountPoint: mountPoint) }
        return mountPoint
    }
}
