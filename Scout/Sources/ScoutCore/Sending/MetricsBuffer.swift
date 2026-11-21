import ScoutProtocol

/// The samples Scout holds until Hive has them (§5): the last hour whole, and for the 23 hours before
/// it each minute's figures, without processes. Nothing older than a day is kept. Times are taken from
/// the newest sample, and counts are capped too, so a clock set back can't make it grow.
struct MetricsBuffer {
    static let wholeSeconds: Int64 = 3_600
    static let keptSeconds: Int64 = 86_400
    static let wholeSampleCount = Int(wholeSeconds / SampleSchedule.intervalSeconds)
    static let minuteCount = Int((keptSeconds - wholeSeconds) / 60)

    struct Batch: Equatable {
        var samples: [MetricsSample]
        var minutes: [MetricsMinute]
    }

    /// From the last hour, in the order they were taken.
    private(set) var samples: [MetricsSample] = []
    private(set) var minutes: [MetricsMinute] = []
    /// Samples older than the hour from a minute that hasn't ended yet.
    private var closingMinute: (startsAt: Int64, samples: [MetricsSample])?
    private var inFlight: Batch?
    private var newestSettled: Int64?

    var heldSampleCount: Int {
        samples.count + (closingMinute?.samples.count ?? 0)
    }

    var heldMinuteCount: Int {
        minutes.count
    }

    mutating func add(_ sample: MetricsSample) {
        samples.append(sample)
        age(now: sample.takenAt)
    }

    /// The newest sample alone when it hasn't been sent, so Hive is current at once, otherwise the
    /// oldest of the rest. Nil when there's nothing to send or a batch is already out.
    mutating func nextBatch() -> Batch? {
        guard inFlight == nil else { return nil }
        let batch: Batch
        if let newest = samples.last, newest.takenAt > newestSettled ?? .min {
            batch = Batch(samples: [newest], minutes: [])
        } else if !minutes.isEmpty {
            batch = Batch(samples: [], minutes: Array(minutes.prefix(MetricsReport.largestMinuteCount)))
        } else if !samples.isEmpty {
            batch = Batch(samples: Array(samples.prefix(MetricsReport.largestSampleCount)), minutes: [])
        } else {
            return nil
        }
        inFlight = batch
        return batch
    }

    /// Delivered and refused batches are let go; a returned one is offered again.
    mutating func settle(_ outcome: ReportOutcome) {
        guard let batch = inFlight else { return }
        inFlight = nil
        guard outcome != .returned else { return }
        let sampleTimes = Set(batch.samples.map(\.takenAt))
        let minuteStarts = Set(batch.minutes.map(\.startsAt))
        samples.removeAll { sampleTimes.contains($0.takenAt) }
        minutes.removeAll { minuteStarts.contains($0.startsAt) }
        if let newest = sampleTimes.max() { newestSettled = max(newestSettled ?? newest, newest) }
    }

    private mutating func age(now: Int64) {
        let hourAgo = now - Self.wholeSeconds
        // A sample on its way to Hive stays whole until it's settled, so it can't be sent twice.
        while let oldest = samples.first,
              oldest.takenAt <= hourAgo || samples.count > Self.wholeSampleCount,
              !(inFlight?.samples.contains { $0.takenAt == oldest.takenAt } ?? false) {
            samples.removeFirst()
            fold(oldest)
        }
        if let closingMinute, closingMinute.startsAt + 60 <= hourAgo { closeMinute() }
        while let oldest = minutes.first, oldest.startsAt <= now - Self.keptSeconds { minutes.removeFirst() }
        if minutes.count > Self.minuteCount { minutes.removeFirst(minutes.count - Self.minuteCount) }
    }

    private mutating func fold(_ sample: MetricsSample) {
        let startsAt = sample.takenAt - ((sample.takenAt % 60) + 60) % 60
        if let closingMinute, closingMinute.startsAt != startsAt { closeMinute() }
        closingMinute = (startsAt, (closingMinute?.samples ?? []) + [sample])
    }

    private mutating func closeMinute() {
        guard let closingMinute else { return }
        minutes.append(MinuteRollup.minute(startingAt: closingMinute.startsAt, of: closingMinute.samples))
        self.closingMinute = nil
    }
}
