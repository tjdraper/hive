import Foundation
import HiveKit

/// When a job's times fall, in the Hive Mac's local time (§11).
struct ScheduleCalendar: Sendable {
    let calendar: Calendar

    /// The first of `times` after `date`. A time that a daylight saving change skips falls at the first
    /// moment after the gap, and a time the change repeats falls only on its first pass.
    func nextRun(after date: Date, times: [TimeOfDay]) -> Date? {
        guard !times.isEmpty else { return nil }
        var day = calendar.startOfDay(for: date)
        // Today's times may all have passed, and a time skipped late in the day can fall on the next.
        for _ in 0 ..< 3 {
            if let next = times.compactMap({ occurrence(of: $0, onDayStarting: day) }).filter({ $0 > date }).min() {
                return next
            }
            guard let following = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = calendar.startOfDay(for: following)
        }
        return nil
    }

    /// Worked out for each day from its start, so a repeated hour can't give the same time twice.
    private func occurrence(of time: TimeOfDay, onDayStarting day: Date) -> Date? {
        calendar.nextDate(
            after: day.addingTimeInterval(-1),
            matching: DateComponents(hour: time.hour, minute: time.minute, second: 0),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    /// Identifies the times and time zone a stored next run was worked out for.
    func key(for times: [TimeOfDay]) -> String {
        ([calendar.timeZone.identifier] + times.sorted().map { String($0.hour * 60 + $0.minute) }).joined(separator: " ")
    }
}
