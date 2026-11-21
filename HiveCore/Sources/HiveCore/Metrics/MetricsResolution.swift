/// How finely a server's figures are kept, and for how long (§6). Times are seconds since 1970 on the
/// server's clock.
enum MetricsResolution: CaseIterable, Sendable {
    case tenSeconds
    case minute
    case hour

    var seconds: Int64 {
        switch self {
        case .tenSeconds: 10
        case .minute: 60
        case .hour: 3_600
        }
    }

    var keptSeconds: Int64 {
        switch self {
        case .tenSeconds: 86_400
        case .minute: 7 * 86_400
        case .hour: 365 * 86_400
        }
    }

    var tableSuffix: String {
        switch self {
        case .tenSeconds: "TenSeconds"
        case .minute: "Minute"
        case .hour: "Hour"
        }
    }

    /// The start of the period `time` falls in, for times before 1970 too.
    func periodStart(of time: Int64) -> Int64 {
        time - ((time % seconds) + seconds) % seconds
    }
}
