import ScoutProtocol

/// Reads the space on each local filesystem. Network and memory filesystems are left out: `statvfs`
/// on a network mount that's stopped answering blocks, and memory ones hold nothing that fills a disk.
struct FilesystemReader {
    /// Filesystems that live on the server's own disks.
    static let localTypes: Set<Substring> = [
        "ext2", "ext3", "ext4", "xfs", "btrfs", "zfs", "bcachefs", "f2fs", "jfs", "reiserfs",
        "vfat", "exfat", "ntfs", "ntfs3",
    ]

    let space: FilesystemSpaceReader

    func read(mounts: [Mount], on eventLoop: ScoutEventLoop) async -> [FilesystemFigures] {
        var figures: [FilesystemFigures] = []
        for mount in Self.localFilesystems(in: mounts) {
            let space = await space.space(of: mount.mountPoint, on: eventLoop)
            figures.append(FilesystemFigures(mountPoint: mount.mountPoint, device: mount.source, type: String(mount.type), space: space))
        }
        return figures
    }

    /// Each filesystem once, however many places it's mounted, such as a bind mount or Btrfs
    /// subvolumes, which all share one filesystem's space. Where it's mounted more than once, the
    /// shortest mount point stands for it, which is usually where it was mounted first.
    static func localFilesystems(in mounts: [Mount]) -> [Mount] {
        var byDevice: [Substring: Mount] = [:]
        for mount in mounts where localTypes.contains(mount.type) {
            if let chosen = byDevice[mount.device], chosen.mountPoint.utf8.count <= mount.mountPoint.utf8.count { continue }
            byDevice[mount.device] = mount
        }
        return byDevice.values.sorted { $0.mountPoint < $1.mountPoint }
    }
}
