#if os(macOS)
import Darwin
import ScoutProtocol

/// A filesystem a Mac has mounted, as `getfsstat` lists it.
struct MacMount: Equatable {
    var mountPoint: String
    /// Such as `/dev/disk3s5`.
    var device: String
    var type: String
    /// `statfs`' `MNT_` flags.
    var flags: UInt32

    /// The volumes Finder shows, which are the ones a person can fill: the startup disk and drives
    /// they've connected. The system's own volumes, such as `/System/Volumes/Data` and `VM`, share
    /// the startup disk's space and are hidden from Finder, so they'd only repeat it. Read-only ones,
    /// such as a mounted installer, can't fill, apart from the startup disk's sealed system volume,
    /// which stands for it. Network filesystems are left out, as they are on Linux.
    var isReported: Bool {
        let isLocal = flags & UInt32(MNT_LOCAL) != 0
        let isHidden = flags & UInt32(MNT_DONTBROWSE) != 0
        let isReadOnly = flags & UInt32(MNT_RDONLY) != 0
        let isRoot = flags & UInt32(MNT_ROOTFS) != 0
        return isLocal && !isHidden && (!isReadOnly || isRoot)
    }

    /// Without waiting for each filesystem, so one that's stopped answering can't hold up the list.
    static func all() -> [MacMount] {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }
        let buffer = UnsafeMutablePointer<statfs>.allocate(capacity: Int(count))
        defer { buffer.deallocate() }
        let listed = getfsstat(buffer, Int32(Int(count) * MemoryLayout<statfs>.stride), MNT_NOWAIT)
        guard listed > 0 else { return [] }
        return (0 ..< Int(min(listed, count))).map { index in
            var figures = buffer[index]
            return MacMount(
                mountPoint: Self.string(&figures.f_mntonname),
                device: Self.string(&figures.f_mntfromname),
                type: Self.string(&figures.f_fstypename),
                flags: figures.f_flags
            )
        }
    }

    /// One of `statfs`' fixed-size C strings.
    static func string<Tuple>(_ tuple: inout Tuple) -> String {
        withUnsafeBytes(of: &tuple) { bytes in
            // swiftlint:disable:next optional_data_string_conversion
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// A filesystem's figures from `statfs`, whose counts are 64 bits, unlike `statvfs`' on a Mac.
struct MacFilesystemSpace: Equatable {
    var type: String
    var blockSize: UInt64
    var blocks: UInt64
    var freeBlocks: UInt64
    var availableBlocks: UInt64
    var files: UInt64
    var freeFiles: UInt64

    /// APFS has no fixed number of inodes: its free count is what the space left could hold, so it's
    /// left out, as Btrfs' is on Linux. So are those of filesystems that report none, such as exFAT.
    var space: FilesystemSpace {
        FilesystemSpace(
            sizeBytes: blocks * blockSize,
            usedBytes: (blocks - min(freeBlocks, blocks)) * blockSize,
            availableBytes: availableBlocks * blockSize,
            inodes: type == "apfs" || files == 0 ? nil : InodeCounts(used: files - min(freeFiles, files), free: freeFiles)
        )
    }

    static func read(at path: String) -> MacFilesystemSpace? {
        var figures = statfs()
        guard statfs(path, &figures) == 0 else { return nil }
        return MacFilesystemSpace(
            type: MacMount.string(&figures.f_fstypename),
            blockSize: UInt64(figures.f_bsize),
            blocks: figures.f_blocks,
            freeBlocks: figures.f_bfree,
            availableBlocks: figures.f_bavail,
            files: figures.f_files,
            freeFiles: figures.f_ffree
        )
    }
}

/// Reads the space on each of a Mac's volumes that a person can fill.
struct MacFilesystemReader {
    let space = FilesystemSpaceReader { MacFilesystemSpace.read(at: $0)?.space }

    func read(on eventLoop: ScoutEventLoop) async -> [FilesystemFigures] {
        var figures: [FilesystemFigures] = []
        for mount in MacMount.all().filter(\.isReported).sorted(by: { $0.mountPoint < $1.mountPoint }) {
            let space = await space.space(of: mount.mountPoint, on: eventLoop)
            figures.append(FilesystemFigures(mountPoint: mount.mountPoint, device: mount.device, type: mount.type, space: space))
        }
        return figures
    }
}
#endif
