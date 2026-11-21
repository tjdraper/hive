#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ScoutProtocol
import Synchronization

/// One kind of data Scout sends Hive, with a buffer and limits of its own, so a backlog of one kind
/// never holds up or crowds out another (§10). ``SendingCoordinator`` sends from queues in the order
/// it's given them, with metrics first.
public protocol ReportQueue: Sendable {
    /// The next request to send, with `sentAt` (the wall clock in seconds) in its body, or nil when
    /// there's nothing waiting. What it carries is offered again only once it's settled as returned.
    func nextReport(sentAt: Int64) throws -> PendingReport?
    /// Settles the report last given out.
    func settle(_ outcome: ReportOutcome)
}

public struct PendingReport: Sendable {
    public let path: String
    public let body: [UInt8]
}

public enum ReportOutcome: Sendable {
    case delivered
    /// Hive won't keep it, so sending it again would be refused again.
    case refused
    /// Not sent, or not known to have arrived, so it's sent again.
    case returned
}

/// Metrics samples on their way to Hive. Sampling adds to it without waiting, whatever sending is doing.
public final class MetricsQueue: ReportQueue {
    private let buffer = Mutex(MetricsBuffer())

    public init() {}

    public var held: (samples: Int, minutes: Int) {
        buffer.withLock { ($0.heldSampleCount, $0.heldMinuteCount) }
    }

    public func add(_ sample: MetricsSample) {
        buffer.withLock { $0.add(sample) }
    }

    public func nextReport(sentAt: Int64) throws -> PendingReport? {
        guard let batch = buffer.withLock({ $0.nextBatch() }) else { return nil }
        let report = MetricsReport(
            protocolVersion: ScoutProtocolVersion.current,
            sentAt: sentAt,
            samples: batch.samples,
            minutes: batch.minutes
        )
        do {
            return PendingReport(path: ScoutEndpoint.metrics, body: Array(try JSONEncoder().encode(report)))
        } catch {
            // Only a figure that isn't a finite number fails, and it would fail every time.
            settle(.refused)
            throw error
        }
    }

    public func settle(_ outcome: ReportOutcome) {
        buffer.withLock { $0.settle(outcome) }
    }
}
