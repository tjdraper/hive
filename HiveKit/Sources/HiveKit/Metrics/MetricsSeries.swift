/// A server's figures over a range, in buckets Hive sizes so any range comes back as a few hundred
/// (§6). Times are seconds since 1970 on the server's clock.
public struct MetricsSeries: Codable, Hashable, Sendable {
    /// Every bucket starts on a multiple of this.
    public let bucketSeconds: Int64
    /// The server's own figures first, then each filesystem, disk and interface by name. A subject
    /// with nothing kept in the range is left out.
    public let subjects: [MetricsSeriesSubject]

    public init(bucketSeconds: Int64, subjects: [MetricsSeriesSubject]) {
        self.bucketSeconds = bucketSeconds
        self.subjects = subjects
    }
}

public struct MetricsSeriesSubject: Codable, Hashable, Sendable {
    public let kind: MetricsSubjectKind
    /// The mount point, disk or interface. Nil for the server's own figures.
    public let name: String?
    /// A filesystem's device, such as `/dev/vda1`, and type, such as `ext4`, as last reported.
    public let device: String?
    public let filesystemType: String?
    /// Only the buckets something was kept in, oldest first, so a missing one is a gap. Where Hive
    /// keeps only a longer period's figures, such as minutes a Scout held while Hive was unreachable,
    /// each bucket in the period has the period's.
    public let bucketStarts: [Int64]
    public let figures: [MetricsFigureSeries]

    public init(
        kind: MetricsSubjectKind,
        name: String?,
        device: String? = nil,
        filesystemType: String? = nil,
        bucketStarts: [Int64],
        figures: [MetricsFigureSeries]
    ) {
        self.kind = kind
        self.name = name
        self.device = device
        self.filesystemType = filesystemType
        self.bucketStarts = bucketStarts
        self.figures = figures
    }
}

/// One figure's values, a value for each of its subject's buckets.
public struct MetricsFigureSeries: Codable, Hashable, Sendable {
    public let figure: MetricsFigure
    public let average: [Double?]
    /// Nil for totals, such as a disk's size, whose highest is their average.
    public let highest: [Double?]?
    /// Kept only where a dip matters, such as available memory and space (§6).
    public let lowest: [Double?]?

    public init(figure: MetricsFigure, average: [Double?], highest: [Double?]?, lowest: [Double?]?) {
        self.figure = figure
        self.average = average
        self.highest = highest
        self.lowest = lowest
    }
}
