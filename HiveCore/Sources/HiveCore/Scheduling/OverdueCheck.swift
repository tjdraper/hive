import Foundation
import HiveKit

/// Whether a job has gone without a complete snapshot for longer than its times allow (§13).
struct OverdueCheck: Sendable {
    /// Room for a run to finish when it starts behind every other job due at the same time.
    static let grace: TimeInterval = 3 * 60 * 60

    let schedule: ScheduleCalendar

    /// When the job became overdue, or nil if it isn't. `since` is its last complete snapshot, or when
    /// it was added if it has none. It's overdue once the first of its times after that is `grace` past.
    /// A running job isn't, since its run ends in a snapshot or a failure, and a first run can take hours.
    func overdueSince(_ since: Date, times: [TimeOfDay], isRunning: Bool, now: Date) -> Date? {
        guard !isRunning, let due = schedule.nextRun(after: since, times: times) else { return nil }
        let deadline = due.addingTimeInterval(Self.grace)
        return now >= deadline ? deadline : nil
    }
}
