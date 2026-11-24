import Foundation

/// One server on the dashboard: whether it's reporting, its latest figures and its last hour.
public struct ServerMetricsSummary: Codable, Hashable, Sendable {
    public let serverID: UUID
    public let reporting: MetricsReporting
    /// Hive's clock, when the server last sent anything, kept or refused.
    public let lastReportAt: Date?
    public let latest: ServerMetricsLatest?
    /// Each minute of the last hour, on the server's clock, that something was kept in, oldest first.
    public let lastHour: [MetricsSparkPoint]

    public init(
        serverID: UUID,
        reporting: MetricsReporting,
        lastReportAt: Date?,
        latest: ServerMetricsLatest?,
        lastHour: [MetricsSparkPoint]
    ) {
        self.serverID = serverID
        self.reporting = reporting
        self.lastReportAt = lastReportAt
        self.latest = latest
        self.lastHour = lastHour
    }
}

public enum MetricsReporting: String, Codable, Hashable, Sendable {
    /// Its Scout hasn't sent anything since it enrolled, or none is enrolled.
    case waiting
    case reporting
    /// Nothing for the last 3 minutes.
    case stopped
    /// Its samples are refused for being too far ahead of Hive's clock.
    case clockAhead
    /// Its figures are refused for another reason, which ``ScoutState/lastRefusal`` gives.
    case refused
}

/// A server's newest sample, as the dashboard shows it. Live updates carry one each time a server's
/// newest sample changes.
public struct ServerMetricsLatest: Codable, Hashable, Sendable {
    public let serverID: UUID
    /// Seconds since 1970 on the server's clock.
    public let takenAt: Int64
    public let cores: Int?
    public let cpu: CPUShares?
    public let load: LoadFigures?
    public let memory: MemoryUse?
    /// The local filesystem with the largest share used.
    public let fullestFilesystem: FilesystemUse?

    public init(
        serverID: UUID,
        takenAt: Int64,
        cores: Int?,
        cpu: CPUShares?,
        load: LoadFigures?,
        memory: MemoryUse?,
        fullestFilesystem: FilesystemUse?
    ) {
        self.serverID = serverID
        self.takenAt = takenAt
        self.cores = cores
        self.cpu = cpu
        self.load = load
        self.memory = memory
        self.fullestFilesystem = fullestFilesystem
    }
}

/// Shares of every core's time together, from 0 to 1. The rest was idle.
public struct CPUShares: Codable, Hashable, Sendable {
    public let user: Double
    public let system: Double
    public let ioWait: Double
    public let steal: Double

    public init(user: Double, system: Double, ioWait: Double, steal: Double) {
        self.user = user
        self.system = system
        self.ioWait = ioWait
        self.steal = steal
    }
}

public struct LoadFigures: Codable, Hashable, Sendable {
    public let oneMinute: Double
    public let fiveMinutes: Double
    public let fifteenMinutes: Double

    public init(oneMinute: Double, fiveMinutes: Double, fifteenMinutes: Double) {
        self.oneMinute = oneMinute
        self.fiveMinutes = fiveMinutes
        self.fifteenMinutes = fifteenMinutes
    }
}

/// Memory in use is the total less what's available, which counts cache the kernel can drop.
public struct MemoryUse: Codable, Hashable, Sendable {
    public let totalBytes: UInt64
    public let availableBytes: UInt64
    public let swapTotalBytes: UInt64
    public let swapUsedBytes: UInt64

    public init(totalBytes: UInt64, availableBytes: UInt64, swapTotalBytes: UInt64, swapUsedBytes: UInt64) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapUsedBytes = swapUsedBytes
    }
}

/// Used and available don't add up to the size: some space is kept back for root.
public struct FilesystemUse: Codable, Hashable, Sendable {
    public let mountPoint: String
    public let sizeBytes: UInt64
    public let usedBytes: UInt64
    public let availableBytes: UInt64

    public init(mountPoint: String, sizeBytes: UInt64, usedBytes: UInt64, availableBytes: UInt64) {
        self.mountPoint = mountPoint
        self.sizeBytes = sizeBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
    }

    /// The share used as `df` shows it, of what's usable without root's reserve.
    public var usedShare: Double {
        let usable = Double(usedBytes) + Double(availableBytes)
        return usable > 0 ? Double(usedBytes) / usable : 0
    }
}

/// A minute of a sparkline. Times are seconds since 1970 on the server's clock.
public struct MetricsSparkPoint: Codable, Hashable, Sendable {
    public let startsAt: Int64
    /// User, system, I/O wait and steal together, from 0 to 1.
    public let cpuBusy: Double?
    /// The share of memory in use, from 0 to 1.
    public let memoryUsed: Double?

    public init(startsAt: Int64, cpuBusy: Double?, memoryUsed: Double?) {
        self.startsAt = startsAt
        self.cpuBusy = cpuBusy
        self.memoryUsed = memoryUsed
    }
}
