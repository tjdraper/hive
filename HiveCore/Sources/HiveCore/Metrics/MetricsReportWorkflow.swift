import Foundation
import os
import ScoutProtocol
import Synchronization

enum MetricsReportOutcome: Equatable {
    case kept
    case refused(ScoutRefusal.Reason)
    /// Hive doesn't accept the Scout's protocol version, so it has to be updated.
    case protocolNotAccepted
    /// Hive couldn't keep them, so Scout holds on to them and sends them again.
    case unavailable
}

/// A Scout sending figures for the server its session is for. The server comes from the session, never
/// from what the Scout sends, so a Scout can't write another server's figures.
struct MetricsReportWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Metrics")

    private struct Version: Decodable {
        let protocolVersion: Int
    }

    let store: MetricsStore
    let limiter: MetricsRateLimiter
    let now: @Sendable () -> Date

    /// False when the server's Scout has sent more often than Hive takes, checked before its body is read.
    func admits(_ serverID: UUID) -> Bool {
        guard limiter.admit(serverID, at: now()) else {
            Self.logger.error("Refused a Scout's figures: sent too often")
            return false
        }
        return true
    }

    func keep(_ body: Data, forServer serverID: UUID) -> MetricsReportOutcome {
        // The version first, so a Scout whose reports have changed shape is told to update rather
        // than that its figures are wrong.
        guard let version = try? JSONDecoder().decode(Version.self, from: body) else {
            return refuse(.valueOutOfRange, forServer: serverID)
        }
        guard ScoutProtocolVersion.isAccepted(version.protocolVersion) else {
            Self.logger.error("Refused a Scout's figures on protocol version \(version.protocolVersion, privacy: .public)")
            return .protocolNotAccepted
        }
        // A number that doesn't fit its type, such as a negative byte count, fails here.
        guard let report = try? JSONDecoder().decode(MetricsReport.self, from: body) else {
            return refuse(.valueOutOfRange, forServer: serverID)
        }

        let start = ContinuousClock.now
        do {
            switch try store.keep(report, forServer: serverID, at: now()) {
            case .kept(let samples, let minutes):
                let duration = ContinuousClock.now - start
                Self.logger.info(
                    "Kept \(samples, privacy: .public) samples and \(minutes, privacy: .public) minutes in \(duration, privacy: .public)"
                )
                return .kept
            case .refused(let reason):
                Self.logger.error("Refused a Scout's figures: \(reason.rawValue, privacy: .public)")
                return .refused(reason)
            }
        } catch {
            Self.logger.error("Couldn't keep a Scout's figures: \(String(describing: error), privacy: .public)")
            return .unavailable
        }
    }

    /// For a request refused before it reached the store, such as one too large to read.
    func refuse(_ reason: ScoutRefusal.Reason, forServer serverID: UUID) -> MetricsReportOutcome {
        Self.logger.error("Refused a Scout's figures: \(reason.rawValue, privacy: .public)")
        do {
            try store.recordRefusal(reason, forServer: serverID, at: now())
        } catch {
            Self.logger.error("Couldn't record a refusal: \(String(describing: error), privacy: .public)")
        }
        return .refused(reason)
    }
}

/// How often each server's Scout may send, kept in memory. Scout sends once a sample, and a day's
/// backlog in under twenty requests, so this only stops one that's been taken over.
final class MetricsRateLimiter: Sendable {
    static let largestRequestsPerMinute = 60

    private let windows = Mutex<[UUID: (startsAt: Date, count: Int)]>([:])

    func admit(_ serverID: UUID, at now: Date) -> Bool {
        windows.withLock { windows in
            var window = windows[serverID] ?? (now, 0)
            if now.timeIntervalSince(window.startsAt) >= 60 || now < window.startsAt { window = (now, 0) }
            guard window.count < Self.largestRequestsPerMinute else { return false }
            window.count += 1
            windows[serverID] = window
            return true
        }
    }
}
