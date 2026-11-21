@testable import ScoutCore
import ScoutProtocol
import Testing

struct FilesystemReaderTests {
    /// Shaped like a server's: a Btrfs root with a subvolume and a bind mount, an ext4 data disk, and
    /// the memory, network and container filesystems a server mounts too.
    private static let serverMounts = """
        25 1 0:38 /@ / rw,noatime shared:1 - btrfs /dev/vda2 rw,ssd,space_cache=v2,subvolid=256,subvol=/@
        26 25 0:38 /@home /home rw,noatime shared:2 - btrfs /dev/vda2 rw,ssd,space_cache=v2,subvolid=257,subvol=/@home
        27 25 0:23 / /proc rw,nosuid,nodev,noexec,relatime shared:3 - proc proc rw
        28 25 0:24 / /run rw,nosuid,nodev shared:4 - tmpfs tmpfs rw,size=1639196k,mode=755
        29 25 253:1 / /srv/backup\\040drive rw,relatime shared:5 - ext4 /dev/mapper/data-backup rw
        30 25 0:38 /@/var/www /srv/www rw,noatime shared:6 - btrfs /dev/vda2 rw,ssd,subvolid=256,subvol=/@
        31 25 0:45 / /mnt/share rw,relatime shared:7 - nfs4 files.example:/share rw,vers=4.2
        32 25 0:46 / /var/lib/docker/overlay2/abc/merged rw,relatime - overlay overlay rw,lowerdir=/x
        33 25 0:47 / /mnt/remote rw,nosuid,nodev,relatime - fuse.sshfs user@example:/ rw
        """

    @Test("Each local filesystem is sent once, at its shortest mount point, and others are left out")
    func localFilesystems() {
        // Arrange
        let mounts = Mount.all(parsing: Self.serverMounts)

        // Act
        let local = FilesystemReader.localFilesystems(in: mounts)

        // Assert
        #expect(local.map(\.mountPoint) == ["/", "/srv/backup drive"])
        #expect(local.map(\.source) == ["/dev/vda2", "/dev/mapper/data-backup"])
        #expect(local.map(\.type) == ["btrfs", "ext4"])
    }

    @Test("A container's overlay root isn't sent, and its bind-mounted files count as one filesystem")
    func container() throws {
        // Arrange
        let text = try #require(CapturedServer.debian12.files.text(at: "/proc/self/mountinfo"))

        // Act
        let local = FilesystemReader.localFilesystems(in: Mount.all(parsing: text))

        // Assert
        #expect(local.map(\.mountPoint) == ["/etc/hosts"])
    }

    @Test("Mount options after the optional fields are read, however many there are")
    func optionalFields() throws {
        // Arrange
        let line: Substring = "36 35 98:0 /mnt1 /mnt2 rw,noatime master:1 shared:2 - ext3 /dev/root rw,errors=continue"

        // Act
        let mount = try #require(Mount(parsing: line))

        // Assert
        #expect(mount.device == "98:0")
        #expect(mount.mountPoint == "/mnt2")
        #expect(mount.type == "ext3")
        #expect(mount.source == "/dev/root")
        #expect(mount.superOptions == "rw,errors=continue")
    }

    @Test(
        "Processes are hidden only where /proc has hidepid other than 0",
        arguments: [
            ("27 25 0:23 / /proc rw - proc proc rw,hidepid=invisible", true),
            ("27 25 0:23 / /proc rw - proc proc rw,hidepid=2,gid=4", true),
            ("27 25 0:23 / /proc rw - proc proc rw,hidepid=0", false),
            ("27 25 0:23 / /proc rw - proc proc rw", false),
            ("27 25 0:23 / /mnt/proc rw - proc proc rw,hidepid=2", false),
        ]
    )
    func processesHidden(line: String, hidden: Bool) {
        #expect(Mount.all(parsing: line).processesHidden == hidden)
    }

    @Test("A captured /proc mounted with hidepid is noticed")
    func capturedHidepid() throws {
        let hidden = try #require(CapturedServer.debian12Hidepid.files.text(at: "/proc/self/mountinfo"))
        let open = try #require(CapturedServer.debian12.files.text(at: "/proc/self/mountinfo"))
        #expect(Mount.all(parsing: hidden).processesHidden)
        #expect(!Mount.all(parsing: open).processesHidden)
    }

    @Test("Space is read with statvfs, as df shows it")
    func statvfs() throws {
        // Act
        let space = try #require(FilesystemSpaceReader.statvfsSpace(at: "/"))

        // Assert
        #expect(space.sizeBytes > 0)
        #expect(space.usedBytes + space.availableBytes <= space.sizeBytes)
        #expect(FilesystemSpaceReader.statvfsSpace(at: "/nonexistent-scout-test-path") == nil)
    }
}
