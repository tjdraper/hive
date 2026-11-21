/// Memory in use is the total less what's available.
public struct MemoryFigures: Codable, Hashable, Sendable {
    public var totalBytes: UInt64
    /// The kernel's estimate of what could be given to new work without swapping (`MemAvailable`),
    /// counting cache it can drop, unlike "free".
    public var availableBytes: UInt64
    /// Buffers, the page cache and reclaimable kernel caches, as `free` shows them.
    public var cacheBytes: UInt64
    public var swapTotalBytes: UInt64
    public var swapUsedBytes: UInt64
    /// Missing from the first sample.
    public var swapping: Swapping?

    public init(
        totalBytes: UInt64,
        availableBytes: UInt64,
        cacheBytes: UInt64,
        swapTotalBytes: UInt64,
        swapUsedBytes: UInt64,
        swapping: Swapping?
    ) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.cacheBytes = cacheBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapping = swapping
    }
}

/// Pages moved between memory and swap since the previous sample. Swapping in steadily means the
/// server is short of memory; swap that's merely in use often isn't.
public struct Swapping: Codable, Hashable, Sendable {
    public var pagesInPerSecond: Double
    public var pagesOutPerSecond: Double

    public init(pagesInPerSecond: Double, pagesOutPerSecond: Double) {
        self.pagesInPerSecond = pagesInPerSecond
        self.pagesOutPerSecond = pagesOutPerSecond
    }
}
