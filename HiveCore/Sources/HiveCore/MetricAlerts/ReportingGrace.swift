import Foundation
import Synchronization

/// While Scouts may still be backing off, no server counts as stopped (§8): for a while after Hive
/// starts, after the Mac wakes, and after the addresses Hive listens on change.
final class ReportingGrace: Sendable {
    /// Scout waits at most a minute between tries, so this leaves it a few.
    static let length: TimeInterval = 5 * 60
    /// Less time asleep than this since the last check isn't taken for the Mac sleeping, since the two
    /// clocks it's measured with drift apart a little.
    static let shortestSleep: Duration = .seconds(30)

    private struct State {
        var until: Date
        var timeAsleep: Duration
        var listeningHosts: [String]?
    }

    private let state: Mutex<State>
    private let timeAsleep: @Sendable () -> Duration

    /// `timeAsleep` is how long the Mac has slept since some fixed moment, such as `MacSleepClock`'s.
    init(startedAt: Date, timeAsleep: @escaping @Sendable () -> Duration) {
        self.timeAsleep = timeAsleep
        state = Mutex(State(until: startedAt.addingTimeInterval(Self.length), timeAsleep: timeAsleep(), listeningHosts: nil))
    }

    /// Notes a wake or a change of addresses since the last call, starting the grace again.
    func isInGrace(at now: Date, listeningHosts: [String]) -> Bool {
        let asleep = timeAsleep()
        return state.withLock { state in
            let woke = asleep - state.timeAsleep >= Self.shortestSleep
            let moved = state.listeningHosts.map { $0 != listeningHosts } ?? false
            if woke || moved { state.until = max(state.until, now.addingTimeInterval(Self.length)) }
            state.timeAsleep = asleep
            state.listeningHosts = listeningHosts
            return now < state.until
        }
    }
}

/// How long the Mac has slept since Hive started. Hive needs no notification for it: the continuous
/// clock goes on while the Mac sleeps and the suspending clock doesn't, so their difference grows by
/// each sleep, Power Nap's dark wakes included.
struct MacSleepClock: Sendable {
    private let continuousStart = ContinuousClock.now
    private let suspendingStart = SuspendingClock.now

    func timeAsleep() -> Duration {
        (ContinuousClock.now - continuousStart) - (SuspendingClock.now - suspendingStart)
    }
}
