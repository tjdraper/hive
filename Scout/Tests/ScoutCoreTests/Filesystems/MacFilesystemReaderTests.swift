#if os(macOS)
import Darwin
@testable import ScoutCore
import ScoutProtocol
import Testing

struct MacFilesystemReaderTests {
    private static let local = UInt32(MNT_LOCAL)
    private static let readOnly = UInt32(MNT_RDONLY)
    private static let hidden = UInt32(MNT_DONTBROWSE)
    private static let root = UInt32(MNT_ROOTFS)

    /// What `getfsstat` listed on a Mac with two external drives, one holding a backup volume.
    private static let captured = [
        MacMount(mountPoint: "/", device: "/dev/disk3s1s1", type: "apfs", flags: local | readOnly | root),
        MacMount(mountPoint: "/dev", device: "devfs", type: "devfs", flags: local | hidden),
        MacMount(mountPoint: "/System/Volumes/VM", device: "/dev/disk3s6", type: "apfs", flags: local | hidden),
        MacMount(mountPoint: "/System/Volumes/Preboot", device: "/dev/disk3s2", type: "apfs", flags: local | hidden),
        MacMount(mountPoint: "/System/Volumes/Data", device: "/dev/disk3s5", type: "apfs", flags: local | hidden),
        MacMount(mountPoint: "/System/Volumes/Data/home", device: "map auto_home", type: "autofs", flags: hidden),
        MacMount(mountPoint: "/Volumes/Recovery", device: "/dev/disk3s3", type: "apfs", flags: local | hidden),
        MacMount(mountPoint: "/Volumes/ivy-ext-02", device: "/dev/disk9s1", type: "apfs", flags: local),
        MacMount(mountPoint: "/Volumes/ivy-ext-01", device: "/dev/disk7s1", type: "apfs", flags: local),
        MacMount(mountPoint: "/Volumes/Hive", device: "/dev/disk7s2", type: "apfs", flags: local),
        MacMount(mountPoint: "/Users/tj/OrbStack", device: "OrbStack:/OrbStack", type: "nfs", flags: 0),
        MacMount(mountPoint: "/Volumes/Amp", device: "/dev/disk15s1", type: "apfs", flags: local | readOnly),
    ]

    @Test("The startup disk and connected drives are reported, and the system's own volumes aren't")
    func reported() {
        // Act
        let reported = Self.captured.filter(\.isReported).map(\.mountPoint)

        // Assert: the system's volumes share the startup disk's space, the installer is read-only,
        // and OrbStack's share is a network filesystem.
        #expect(reported == ["/", "/Volumes/ivy-ext-02", "/Volumes/ivy-ext-01", "/Volumes/Hive"])
    }

    @Test("Space is worked out as df does, from the blocks used rather than those available")
    func space() {
        // Arrange: the startup disk above, in 4 KB blocks.
        let figures = MacFilesystemSpace(
            type: "apfs",
            blockSize: 4_096,
            blocks: 120_699_413,
            freeBlocks: 7_083_002,
            availableBlocks: 7_082_025,
            files: 283_565_209,
            freeFiles: 283_078_400
        )

        // Act
        let space = figures.space

        // Assert: APFS has no fixed number of inodes, so they're left out.
        #expect(space == FilesystemSpace(
            sizeBytes: 120_699_413 * 4_096,
            usedBytes: (120_699_413 - 7_083_002) * 4_096,
            availableBytes: 7_082_025 * 4_096,
            inodes: nil
        ))
    }

    @Test("Inodes are reported where a filesystem has a fixed number, and left out where it reports none")
    func inodes() {
        // Arrange
        let hfs = MacFilesystemSpace(
            type: "hfs", blockSize: 4_096, blocks: 100, freeBlocks: 40, availableBlocks: 40, files: 1_000, freeFiles: 700
        )
        let exfat = MacFilesystemSpace(
            type: "exfat", blockSize: 4_096, blocks: 100, freeBlocks: 40, availableBlocks: 40, files: 0, freeFiles: 0
        )

        // Act / Assert
        #expect(hfs.space.inodes == InodeCounts(used: 300, free: 700))
        #expect(exfat.space.inodes == nil)
    }
}
#endif
