import Foundation
import Synchronization

struct FailedAttemptPolicy: Sendable {
    static let signIn = FailedAttemptPolicy(maximumFailures: 5, window: 15 * 60, lockout: 15 * 60, maximumTracked: 10000)
    static let pairing = signIn

    let maximumFailures: Int
    let window: TimeInterval
    let lockout: TimeInterval
    /// Bounds the memory an attacker with many addresses can take. Past it, the oldest are forgotten.
    let maximumTracked: Int
}

/// Locks out an address or a device after repeated failures, and never everyone at once, which would
/// let anyone on the internet lock you out.
final class FailedAttemptLimiter<Key: Hashable & Sendable>: Sendable {
    private struct Record {
        var failures: [Date] = []
        var lockedUntil: Date?

        var lastActivity: Date {
            max(failures.last ?? .distantPast, lockedUntil ?? .distantPast)
        }
    }

    private let policy: FailedAttemptPolicy
    private let records = Mutex<[Key: Record]>([:])

    init(policy: FailedAttemptPolicy) {
        self.policy = policy
    }

    func isLockedOut(_ key: Key, at now: Date) -> Bool {
        records.withLock { records in
            guard let lockedUntil = records[key]?.lockedUntil else { return false }
            return now < lockedUntil
        }
    }

    func recordFailure(_ key: Key, at now: Date) {
        records.withLock { records in
            var record = records[key] ?? Record()
            if let lockedUntil = record.lockedUntil, now >= lockedUntil { record = Record() }
            record.failures = record.failures.filter { now.timeIntervalSince($0) < policy.window } + [now]
            if record.failures.count >= policy.maximumFailures {
                record.lockedUntil = now.addingTimeInterval(policy.lockout)
                record.failures = []
            }
            records[key] = record
            forgetOldest(in: &records)
        }
    }

    func reset(_ key: Key) {
        _ = records.withLock { $0.removeValue(forKey: key) }
    }

    private func forgetOldest(in records: inout [Key: Record]) {
        guard records.count > policy.maximumTracked else { return }
        let excess = records.count - policy.maximumTracked
        for key in records.sorted(by: { $0.value.lastActivity < $1.value.lastActivity }).prefix(excess).map(\.key) {
            records.removeValue(forKey: key)
        }
    }
}
