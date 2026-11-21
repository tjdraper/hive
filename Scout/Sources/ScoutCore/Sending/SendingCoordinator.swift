#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ScoutProtocol
import Synchronization

public enum SendingError: Error, Equatable {
    case protocolNotAccepted(hiveVersion: Int)
    /// Hive answered 429: this Scout sent more often than Hive takes.
    case tooOften
    case unexpectedStatus(UInt)
}

/// Sends what Scout holds to Hive: keeps a connection open to the first of its addresses that answers
/// with the pinned key, sends after every sample until nothing is waiting, and waits longer between
/// tries while Hive can't be reached, so a sleeping Mac doesn't make every server spin.
public final class SendingCoordinator: Sendable {
    /// Between tries while Hive is unreachable, the last repeated.
    static let backoff: [Duration] = [.seconds(10), .seconds(20), .seconds(40), .seconds(60)]
    /// While Hive refuses this Scout for good, such as after it was removed. Enrolling again and
    /// reloading (A4) connects at once.
    static let refusedRetry: Duration = .seconds(3_600)
    /// How long Hive's lockout of the server's address lasts.
    static let lockoutWait: Duration = .seconds(15 * 60)

    private let enrollment: SavedEnrollment
    private let connector: any HiveConnecting
    private let metrics: MetricsQueue
    /// Metrics first, so a backlog of any other kind never holds up a sample (§10).
    private let queues: [any ReportQueue]
    private let log: @Sendable (String) -> Void
    private let now: @Sendable () -> Int64
    private let wait: @Sendable (Duration) async throws -> Void
    private let progress = Mutex(SendingStatus())

    /// - Parameters:
    ///   - now: the wall clock, in seconds since 1970.
    ///   - wait: waits for a time, throwing when cancelled.
    public init(
        enrollment: SavedEnrollment,
        connector: any HiveConnecting,
        metrics: MetricsQueue,
        log: @escaping @Sendable (String) -> Void,
        now: @escaping @Sendable () -> Int64,
        wait: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.enrollment = enrollment
        self.connector = connector
        self.metrics = metrics
        queues = [metrics]
        self.log = log
        self.now = now
        self.wait = wait
    }

    /// Where sending stands, for `hive-scout status`.
    public var status: SendingStatus {
        var status = progress.withLock { $0 }
        (status.heldSamples, status.heldMinutes) = metrics.held
        status.updatedAt = now()
        return status
    }

    /// Sends after each of `marks` until they end.
    public func run(marks: AsyncStream<Void>) async throws {
        var marks = marks.makeAsyncIterator()
        var keeper = ScoutSessionKeeper(enrollment: enrollment)
        var failures = 0
        while true {
            let pause: Duration
            do {
                try await connect { connection in
                    try await keepSending(on: connection, keeper: &keeper, marks: &marks, failures: &failures)
                }
                return
            } catch let error as CancellationError {
                throw error
            } catch {
                // A connection that was working, closed by Hive restarting or by its idle timeout, is
                // opened again at once. Failing again counts as unreachable.
                let wasSending = progress.withLock { status in
                    defer { if status.state == .sending { status.state = .connecting } }
                    return status.state == .sending
                }
                if wasSending, !(error is ScoutSignInError), !(error is SendingError) { continue }
                pause = handle(error, failures: failures)
                failures += 1
            }
            try await wait(pause)
        }
    }

    /// Tries each address in turn, like enrolling. Only a Hive that answered decides; an address that
    /// couldn't be reached, or showed another key, moves on to the next.
    private func connect(_ body: (any HiveRequesting) async throws -> Void) async throws {
        var lastError: (any Error)?
        var keyRefused = false
        for address in enrollment.hiveAddresses {
            do {
                try await connector.withConnection(to: address, pin: enrollment.hivePin, body)
                return
            } catch let error as ScoutSignInError {
                throw error
            } catch let error as SendingError {
                throw error
            } catch let error as CancellationError {
                throw error
            } catch HiveConnectionError.keyNotPinned {
                keyRefused = true
            } catch {
                lastError = error
            }
        }
        // Another key at one address and none at the others is more likely an old address than a
        // Hive that's been reset, so it counts as unreachable.
        throw lastError ?? (keyRefused ? HiveConnectionError.keyNotPinned : HiveConnectionError.closedByHive)
    }

    private func keepSending(
        on connection: any HiveRequesting,
        keeper: inout ScoutSessionKeeper,
        marks: inout AsyncStream<Void>.Iterator,
        failures: inout Int
    ) async throws {
        repeat {
            try await sendWaiting(on: connection, keeper: &keeper)
            if failures > 0 || progress.withLock({ $0.state != .sending }) {
                let held = metrics.held
                log("Sending to Hive, holding \(held.samples) samples and \(held.minutes) minutes")
            }
            failures = 0
            progress.withLock { $0.state = .sending; $0.problem = nil }
        } while await marks.next(isolation: #isolation) != nil
    }

    /// Sends from the queues until none has anything waiting, going back to the first after each.
    private func sendWaiting(on connection: any HiveRequesting, keeper: inout ScoutSessionKeeper) async throws {
        var index = 0
        while index < queues.count {
            let queue = queues[index]
            let token = try await keeper.token(on: connection)
            let report: PendingReport?
            do {
                report = try queue.nextReport(sentAt: now())
            } catch {
                log("Dropped figures that couldn't be sent: \(error)")
                continue
            }
            guard let report else {
                index += 1
                continue
            }
            try await send(report, from: queue, token: token, on: connection, keeper: &keeper)
            index = 0
        }
    }

    private func send(
        _ report: PendingReport,
        from queue: any ReportQueue,
        token: String,
        on connection: any HiveRequesting,
        keeper: inout ScoutSessionKeeper
    ) async throws {
        let answer: HiveAnswer
        do {
            var first = try await connection.send("POST", report.path, body: report.body, token: token)
            // Hive forgets sessions when it restarts.
            if first.status == 401 {
                keeper.forget()
                first = try await connection.send("POST", report.path, body: report.body, token: keeper.token(on: connection))
            }
            answer = first
        } catch {
            queue.settle(.returned)
            throw error
        }

        switch answer.status {
        case 200 ..< 300:
            queue.settle(.delivered)
            progress.withLock { $0.lastDeliveredAt = now(); $0.lastRefusal = nil }
        case 422:
            queue.settle(.refused)
            let reason = (try? JSONDecoder().decode(ScoutRefusal.self, from: Data(answer.body)))?.reason.rawValue ?? "unknown"
            // Logged when the reason changes, so a clock that stays ahead doesn't write to the journal every sample.
            let isNew = progress.withLock { status in
                defer { status.lastRefusal = reason }
                return status.lastRefusal != reason
            }
            if isNew { log("Hive refused samples and they were dropped: \(reason)") }
        case 409:
            queue.settle(.returned)
            let mismatch = try? JSONDecoder().decode(ScoutProtocolMismatch.self, from: Data(answer.body))
            throw SendingError.protocolNotAccepted(hiveVersion: mismatch?.hiveProtocolVersion ?? 0)
        case 429:
            queue.settle(.returned)
            throw SendingError.tooOften
        default:
            queue.settle(.returned)
            throw SendingError.unexpectedStatus(answer.status)
        }
    }

    private struct Stop {
        let state: SendingStatus.State
        let problem: String
        let pause: Duration

        init(_ state: SendingStatus.State, _ problem: String, _ pause: Duration) {
            self.state = state
            self.problem = problem
            self.pause = pause
        }
    }

    /// Records and logs what stopped sending, the first time it does, and says how long to wait.
    private func handle(_ error: any Error, failures: Int) -> Duration {
        let stop = Self.stop(for: error, failures: failures)
        let (state, problem) = (stop.state, stop.problem)
        let isNew = progress.withLock { status in
            defer { status.state = state; status.problem = problem }
            return status.state != state || status.problem != problem && state == .refused
        }
        if isNew {
            log(state == .refused ? "Refused by Hive: \(problem) Trying again hourly." : "\(problem) Holding samples until it answers.")
        }
        return stop.pause
    }

    private static func stop(for error: any Error, failures: Int) -> Stop {
        switch error {
        case HiveConnectionError.keyNotPinned:
            Stop(.refused, "Hive's key isn't the one Scout enrolled with. Enroll again.", refusedRetry)
        case ScoutSignInError.notRecognized:
            Stop(.refused, "Hive doesn't recognize this Scout. It may have been removed. Enroll again.", refusedRetry)
        case ScoutSignInError.protocolNotAccepted, SendingError.protocolNotAccepted:
            Stop(.refused, "Hive doesn't accept this version of Scout. Update Scout.", refusedRetry)
        case ScoutSignInError.lockedOut:
            Stop(.unreachable, "Hive turned away too many attempts from this server.", lockoutWait)
        case SendingError.tooOften:
            Stop(.unreachable, "Hive turned away samples sent more often than it takes.", backoff[min(failures, backoff.count - 1)])
        default:
            Stop(.unreachable, "Couldn't reach Hive: \(error)", backoff[min(failures, backoff.count - 1)])
        }
    }
}
