/// A local filesystem, such as ext4 or XFS. Network and memory filesystems aren't sent.
public struct FilesystemFigures: Codable, Hashable, Sendable {
    public var mountPoint: String
    /// What's mounted, such as `/dev/vda1`.
    public var device: String
    public var type: String
    /// Missing when the filesystem couldn't be read, or didn't answer in time, which usually means its
    /// disk is failing.
    public var space: FilesystemSpace?

    public init(mountPoint: String, device: String, type: String, space: FilesystemSpace?) {
        self.mountPoint = mountPoint
        self.device = device
        self.type = type
        self.space = space
    }
}

/// Used and available don't add up to the size: some space is kept back for root.
public struct FilesystemSpace: Codable, Hashable, Sendable {
    public var sizeBytes: UInt64
    public var usedBytes: UInt64
    /// What users other than root can still write.
    public var availableBytes: UInt64
    /// Missing for filesystems without a fixed number of inodes, such as Btrfs.
    public var inodes: InodeCounts?

    public init(sizeBytes: UInt64, usedBytes: UInt64, availableBytes: UInt64, inodes: InodeCounts?) {
        self.sizeBytes = sizeBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
        self.inodes = inodes
    }
}

/// A filesystem can run out of inodes, one for each file, with space left.
public struct InodeCounts: Codable, Hashable, Sendable {
    public var used: UInt64
    public var free: UInt64

    public init(used: UInt64, free: UInt64) {
        self.used = used
        self.free = free
    }
}
