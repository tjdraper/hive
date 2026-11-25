import Foundation

/// When Hive emails about a server's figures (§8). Each server has its own, starting from `defaults`.
public struct MetricAlertLimits: Codable, Hashable, Sendable {
    /// A filesystem's space, or its inodes, in use.
    public var filesystemUsedPercent: Int
    /// A filesystem forecast to fill within this many days, at the rate it filled over the last week.
    public var filesystemFillDays: Int
    /// Memory available below this share of the total.
    public var memoryAvailablePercent: Int
    /// How long memory has to be short, or swapping in steadily, before it counts.
    public var memoryMinutes: Int
    /// User, system, I/O wait and steal together, as the dashboard shows CPU.
    public var cpuBusyPercent: Int
    public var cpuStealPercent: Int
    /// The one-minute load average for each core.
    public var loadPerCore: Double
    /// How long CPU or load has to be over its limit before it counts.
    public var cpuMinutes: Int

    public static let defaults = MetricAlertLimits(
        filesystemUsedPercent: 90,
        filesystemFillDays: 7,
        memoryAvailablePercent: 10,
        memoryMinutes: 10,
        cpuBusyPercent: 90,
        cpuStealPercent: 20,
        loadPerCore: 2,
        cpuMinutes: 15
    )

    public static let percentRange = 1 ... 100
    public static let fillDaysRange = 1 ... 365
    /// Hive keeps every sample for a day, and works out whether a limit has cleared from the last hour and
    /// the duration before it.
    public static let minutesRange = 1 ... 120
    public static let loadPerCoreRange = 0.1 ... 100.0

    public init(
        filesystemUsedPercent: Int,
        filesystemFillDays: Int,
        memoryAvailablePercent: Int,
        memoryMinutes: Int,
        cpuBusyPercent: Int,
        cpuStealPercent: Int,
        loadPerCore: Double,
        cpuMinutes: Int
    ) {
        self.filesystemUsedPercent = filesystemUsedPercent
        self.filesystemFillDays = filesystemFillDays
        self.memoryAvailablePercent = memoryAvailablePercent
        self.memoryMinutes = memoryMinutes
        self.cpuBusyPercent = cpuBusyPercent
        self.cpuStealPercent = cpuStealPercent
        self.loadPerCore = loadPerCore
        self.cpuMinutes = cpuMinutes
    }

    /// Whether Hive accepts every value.
    public var isValid: Bool {
        [filesystemUsedPercent, memoryAvailablePercent, cpuBusyPercent, cpuStealPercent].allSatisfy(Self.percentRange.contains)
            && Self.fillDaysRange.contains(filesystemFillDays)
            && [memoryMinutes, cpuMinutes].allSatisfy(Self.minutesRange.contains)
            && Self.loadPerCoreRange.contains(loadPerCore)
    }
}

/// Something wrong with a server that Hive has emailed about, or is about to, while it lasts.
public enum MetricAlert: Codable, Hashable, Sendable {
    /// Nothing from the server since `since`, Hive's clock. `withOthers` when other servers stopped at
    /// the same time, which usually means Hive's own connection.
    case stoppedReporting(since: Date, withOthers: Bool)
    /// Its samples are refused for being too far ahead of Hive's clock.
    case clockAhead
    case filesystemFilling(mountPoint: String)
    case memoryShort
    case cpuBusy
}
