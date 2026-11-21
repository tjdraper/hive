/// Sent by Scout to `ScoutEndpoint.metrics` with its session: samples, and minutes from a backlog.
/// Hive keeps one of each per server and time, so sending one again changes nothing.
public struct MetricsReport: Codable, Sendable {
    /// Batches are kept to these, so each request stays small whatever Scout is holding.
    public static let largestSampleCount = 60
    public static let largestMinuteCount = 120

    public let protocolVersion: Int
    /// Scout's clock, in seconds since 1970, as the request was sent. Hive works out the server's
    /// clock offset from it, since the samples may have been taken long before.
    public let sentAt: Int64
    public let samples: [MetricsSample]
    public let minutes: [MetricsMinute]

    public init(protocolVersion: Int, sentAt: Int64, samples: [MetricsSample], minutes: [MetricsMinute]) {
        self.protocolVersion = protocolVersion
        self.sentAt = sentAt
        self.samples = samples
        self.minutes = minutes
    }
}

/// Sent with 422 when Hive turns away what a Scout sent. Scout logs it and drops what was refused,
/// since sending it again would be refused again.
public struct ScoutRefusal: Codable, Sendable {
    /// Open, so an older Scout can still log a reason it doesn't know.
    public struct Reason: RawRepresentable, Codable, Hashable, Sendable {
        /// The server's clock is so far ahead of the time it reported sending at that its samples
        /// can't be placed.
        public static let clockAhead = Reason(rawValue: "clock-ahead")
        public static let tooOld = Reason(rawValue: "too-old")
        public static let tooManySamples = Reason(rawValue: "too-many-samples")
        /// The request was larger than Hive reads.
        public static let tooLarge = Reason(rawValue: "too-large")
        /// More filesystems, disks, interfaces or processes in a sample than Hive keeps.
        public static let tooManyFigures = Reason(rawValue: "too-many-figures")
        /// More new filesystem, disk or interface names in a day than Hive takes from one server.
        public static let tooManyNewNames = Reason(rawValue: "too-many-new-names")
        /// A figure that isn't a finite number in its range, such as a share above 1.
        public static let valueOutOfRange = Reason(rawValue: "value-out-of-range")

        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public let reason: Reason

    public init(reason: Reason) {
        self.reason = reason
    }
}
