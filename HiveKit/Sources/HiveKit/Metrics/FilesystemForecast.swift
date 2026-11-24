/// How fast a filesystem has been filling over the last week, from its hourly figures, and when it
/// fills at that rate.
public struct FilesystemForecast: Codable, Hashable, Sendable {
    public let mountPoint: String
    /// Positive while it fills. Nil without enough hours to tell.
    public let growthBytesPerDay: Double?
    /// Seconds since 1970 on the server's clock. Nil while it's steady or shrinking, or wouldn't fill
    /// within a year.
    public let fillsAt: Int64?

    public init(mountPoint: String, growthBytesPerDay: Double?, fillsAt: Int64?) {
        self.mountPoint = mountPoint
        self.growthBytesPerDay = growthBytesPerDay
        self.fillsAt = fillsAt
    }
}
