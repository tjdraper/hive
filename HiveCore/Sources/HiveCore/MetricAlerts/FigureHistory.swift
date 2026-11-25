import Foundation

/// One figure from each of a server's 10-second samples, oldest first, for whether it stayed over a limit
/// for a while. Durations are counted from the samples' own times, never Hive's clock, so a backlog that
/// arrives late is placed when it was taken, and a gap while nothing was kept never counts as over.
struct FigureHistory {
    /// Scout's.
    static let sampleInterval: Int64 = 10
    /// Samples further apart than this leave a gap: the server, or its Scout, wasn't reporting.
    static let largestGap: Int64 = 60

    /// Times on the server's clock. Samples without the figure, such as the first after Scout starts,
    /// are left out.
    let samples: [(at: Int64, value: Double)]

    /// The average over the `duration` seconds up to `end`, or nil unless samples cover all of it
    /// without a gap.
    func average(over duration: Int64, upTo end: Int64) -> Double? {
        let inside = samples.filter { $0.at > end - duration && $0.at <= end }
        guard let first = inside.first, let last = inside.last,
              first.at - (end - duration) <= Self.sampleInterval, end - last.at <= Self.largestGap,
              zip(inside, inside.dropFirst()).allSatisfy({ $1.at - $0.at <= Self.largestGap })
        else { return nil }
        return inside.reduce(0) { $0 + $1.value } / Double(inside.count)
    }

    /// True once the samples reach back over the whole `period` up to `end`, and at none of them did
    /// the average over the `duration` before it meet `isOver`. Those averages are taken from whatever
    /// samples there are, so a stretch after a gap counts as soon as it starts.
    func hasCleared(_ isOver: (Double) -> Bool, over duration: Int64, for period: Int64, upTo end: Int64) -> Bool {
        guard let first = samples.first, first.at <= end - period + Self.sampleInterval else { return false }
        let recent = samples.filter { $0.at > end - period && $0.at <= end }
        return recent.allSatisfy { sample in
            let window = samples.filter { $0.at > sample.at - duration && $0.at <= sample.at }
            return !isOver(window.reduce(0) { $0 + $1.value } / Double(window.count))
        }
    }
}
