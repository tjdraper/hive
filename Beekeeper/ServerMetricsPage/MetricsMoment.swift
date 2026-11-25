import Foundation
import Observation

/// The moment every chart on a server's page marks: the one under the pointer while it's over a chart,
/// and the one chosen by clicking, whose processes the page shows.
@Observable
final class MetricsMoment {
    var hovered: Date?
    var chosen: Date?

    /// What the charts' figures are read at. Nil shows each one's newest.
    var shown: Date? {
        hovered ?? chosen
    }
}
