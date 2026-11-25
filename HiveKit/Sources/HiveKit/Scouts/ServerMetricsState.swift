import Foundation

/// Whether a server has metrics, and what Hive knows of the Scout reporting them.
public struct ServerMetricsState: Codable, Hashable, Sendable {
    /// True from the first time a Scout enrolls for the server until its metrics are removed. It
    /// survives a restore and a new identity, which a Scout's key doesn't.
    public let hasMetrics: Bool
    /// Nil while a server with metrics waits for its Scout to enroll again, such as after a restore.
    public let scout: ScoutState?

    public init(hasMetrics: Bool, scout: ScoutState?) {
        self.hasMetrics = hasMetrics
        self.scout = scout
    }
}

/// A server's Scout, as it last signed in and reported. What it reported is checked by Hive before
/// it's kept, but it's still the server's word.
public struct ScoutState: Codable, Hashable, Sendable {
    public let enrolledAt: Date
    /// When Hive last heard from it, signing in or sending figures.
    public let lastSeenAt: Date?
    /// When its last figures arrived, kept or refused. Nil until it first sends.
    public let lastReportAt: Date?
    /// Scout's own version, such as "0.1.0".
    public let version: String?
    /// Such as "linux-x86_64".
    public let platform: String?
    /// Such as "Debian GNU/Linux 12 (bookworm)".
    public let distribution: String?
    public let kernel: String?
    /// When the server last started, in seconds since 1970 on its clock, as of its newest sample.
    public let startedAt: Int64?
    /// The server's clock less Hive's, in seconds.
    public let clockOffsetSeconds: Int?
    /// `/proc` hides other users' processes from Scout.
    public let processesHidden: Bool?
    /// Why Hive refused its last figures, such as `clock-ahead`, until it keeps some again.
    public let lastRefusal: String?
    /// Nil while it's current.
    public let update: ScoutUpdate?

    public init(
        enrolledAt: Date,
        lastSeenAt: Date?,
        lastReportAt: Date?,
        version: String?,
        platform: String?,
        distribution: String?,
        kernel: String?,
        startedAt: Int64?,
        clockOffsetSeconds: Int?,
        processesHidden: Bool?,
        lastRefusal: String?,
        update: ScoutUpdate?
    ) {
        self.enrolledAt = enrolledAt
        self.lastSeenAt = lastSeenAt
        self.lastReportAt = lastReportAt
        self.version = version
        self.platform = platform
        self.distribution = distribution
        self.kernel = kernel
        self.startedAt = startedAt
        self.clockOffsetSeconds = clockOffsetSeconds
        self.processesHidden = processesHidden
        self.lastRefusal = lastRefusal
        self.update = update
    }
}

/// Why a server's Scout should be updated.
public enum ScoutUpdate: Codable, Hashable, Sendable {
    /// Hive.app carries a newer release of Scout.
    case newerRelease(version: String)
    /// Hive no longer accepts what this Scout sends, so it's refused until it's updated.
    case protocolNotAccepted
}
