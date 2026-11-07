import Foundation
@testable import HiveCore
import HiveKit
import Testing

/// Snapshots dated in the Hive Mac's time zone, which for these tests is New York's, with daylight saving.
struct TierResolverTests {
    private static let calendar = APIFixture.calendar
    private static let resolver = TierResolver(calendar: calendar)

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components) else { fatalError("Not a date: \(components)") }
        return date
    }

    private static func complete(_ date: Date) -> SnapshotRecord {
        SnapshotRecord(
            id: UUID(),
            jobID: jobID,
            serverID: serverID,
            driveUUID: "drive",
            serverFolder: "server",
            jobFolder: "job",
            folder: SnapshotFolderName.snapshot(at: date),
            state: .complete,
            startedAt: date.addingTimeInterval(-60),
            completedAt: date
        )
    }

    private static func partial(startedAt date: Date) -> SnapshotRecord {
        SnapshotRecord(
            id: UUID(),
            jobID: jobID,
            serverID: serverID,
            driveUUID: "drive",
            serverFolder: "server",
            jobFolder: "job",
            folder: SnapshotFolderName.partial(at: date),
            state: .partial,
            startedAt: date,
            completedAt: nil
        )
    }

    private static let jobID = UUID()
    private static let serverID = UUID()

    private func kept(_ snapshots: [SnapshotRecord], daily: Int, monthly: Int) -> [Date] {
        let decision = Self.resolver.decide(snapshots, tiers: RetentionTiers(dailySnapshots: daily, monthlySnapshots: monthly))
        return snapshots.filter { decision.kept.contains($0.id) }.map(\.date).sorted()
    }

    @Test("Days without a snapshot don't count, so the daily tier reaches back past them")
    func dailySkipsEmptyDays() {
        // Arrange
        let days = [1, 2, 5, 9, 10, 20].map { Self.date(2026, 6, $0) }
        let snapshots = days.map(Self.complete)

        // Act
        let kept = kept(snapshots, daily: 4, monthly: 0)

        // Assert
        #expect(kept == Array(days.suffix(4)))
    }

    @Test("Several runs on one day keep only the day's newest")
    func severalRunsADay() {
        // Arrange
        let times = [
            Self.date(2026, 6, 1, 6), Self.date(2026, 6, 1, 18),
            Self.date(2026, 6, 2, 0, 5), Self.date(2026, 6, 2, 12), Self.date(2026, 6, 2, 23, 55),
        ]

        // Act
        let kept = kept(times.map(Self.complete), daily: 30, monthly: 0)

        // Assert
        #expect(kept == [Self.date(2026, 6, 1, 18), Self.date(2026, 6, 2, 23, 55)])
    }

    @Test("The monthly tier keeps each month's newest, for the newest months that have one, across a year's end")
    func monthlyAcrossYearEnd() {
        // Arrange
        let dates = [
            Self.date(2025, 9, 15), Self.date(2025, 10, 1), Self.date(2025, 10, 31, 23, 59),
            Self.date(2025, 12, 1), Self.date(2025, 12, 31, 23, 30), Self.date(2026, 1, 1, 0, 30),
            Self.date(2026, 1, 20), Self.date(2026, 3, 2),
        ]

        // Act
        let kept = kept(dates.map(Self.complete), daily: 1, monthly: 4)

        // Assert
        #expect(kept == [Self.date(2025, 10, 31, 23, 59), Self.date(2025, 12, 31, 23, 30), Self.date(2026, 1, 20), Self.date(2026, 3, 2)])
    }

    @Test("A month with no snapshot doesn't count, so a long outage ages out no monthly history")
    func monthlySkipsEmptyMonths() {
        // Arrange
        let dates = [Self.date(2025, 1, 10), Self.date(2025, 2, 10), Self.date(2025, 3, 10), Self.date(2026, 3, 10)]

        // Act
        let kept = kept(dates.map(Self.complete), daily: 1, monthly: 3)

        // Assert
        #expect(kept == Array(dates.suffix(3)))
    }

    @Test("Daily and monthly together keep exactly their union and the newest, and nothing else")
    func tiersTogether() {
        // Arrange
        let dates = (1 ... 31).map { Self.date(2026, 5, $0) }
            + (1 ... 30).map { Self.date(2026, 6, $0) }
            + (1 ... 10).map { Self.date(2026, 7, $0) }
        let snapshots = dates.map(Self.complete)

        // Act
        let decision = Self.resolver.decide(snapshots, tiers: RetentionTiers(dailySnapshots: 14, monthlySnapshots: 3))

        // Assert
        let kept = snapshots.filter { decision.kept.contains($0.id) }.map(\.date).sorted()
        let expected = [Self.date(2026, 5, 31)]
            + (27 ... 30).map { Self.date(2026, 6, $0) }
            + (1 ... 10).map { Self.date(2026, 7, $0) }
        #expect(kept == expected)
        #expect(decision.removals.map(\.snapshot.date) == dates.filter { !expected.contains($0) })
        #expect(decision.removals.allSatisfy { $0.reason == .outsideTiers })
        #expect(decision.dailyOnly.map(\.date) == (27 ... 29).map { Self.date(2026, 6, $0) } + (1 ... 9).map { Self.date(2026, 7, $0) })
    }

    @Test("Days are the Hive Mac's: just after midnight is the new day, whatever the UTC folder name says")
    func localDays() {
        // Arrange
        let lateEvening = Self.date(2026, 6, 1, 23, 30)
        let justAfterMidnight = Self.date(2026, 6, 2, 0, 15)

        // Act
        let kept = kept([lateEvening, justAfterMidnight].map(Self.complete), daily: 2, monthly: 0)

        // Assert
        #expect(SnapshotFolderName.snapshot(at: lateEvening).hasPrefix("2026-06-02"))
        #expect(kept == [lateEvening, justAfterMidnight])
    }

    @Test("The day the clocks go back is one day, its repeated hour included")
    func clocksGoBack() throws {
        // Arrange
        let firstOneThirty = try #require(Self.calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 30)))
        let secondOneThirty = firstOneThirty.addingTimeInterval(60 * 60)
        let dates = [
            Self.date(2026, 10, 31, 23, 50), Self.date(2026, 11, 1, 0, 10), firstOneThirty, secondOneThirty, Self.date(2026, 11, 2, 0, 10),
        ]

        // Act
        let kept = kept(dates.map(Self.complete), daily: 3, monthly: 0)

        // Assert
        #expect(Self.calendar.isDate(secondOneThirty, inSameDayAs: firstOneThirty))
        #expect(kept == [Self.date(2026, 10, 31, 23, 50), secondOneThirty, Self.date(2026, 11, 2, 0, 10)])
    }

    @Test("The day the clocks go forward is one day, either side of the skipped hour")
    func clocksGoForward() {
        // Arrange
        let beforeGap = Self.date(2026, 3, 8, 1, 50)
        let afterGap = Self.date(2026, 3, 8, 3, 10)
        let dates = [Self.date(2026, 3, 7, 23, 50), beforeGap, afterGap]

        // Act
        let kept = kept(dates.map(Self.complete), daily: 2, monthly: 0)

        // Assert
        #expect(afterGap.timeIntervalSince(beforeGap) == 20 * 60)
        #expect(kept == [Self.date(2026, 3, 7, 23, 50), afterGap])
    }

    @Test("A job that fails for 30 days keeps the same daily snapshots it had when it started failing")
    func failingJobKeepsHistory() {
        // Arrange
        let before = (1 ... 20).map { Self.date(2026, 4, $0) }.map(Self.complete)
        let tiers = RetentionTiers(dailySnapshots: 7, monthlySnapshots: 2)
        let keptWhenFailingStarted = Self.resolver.decide(before, tiers: tiers).kept

        // Act
        let decisions = (21 ... 50).map { day in
            // Each failed run leaves a partial, which the next one picks up.
            let failing = Self.partial(startedAt: Self.date(2026, 4, 21).addingTimeInterval(Double(day - 21) * 24 * 60 * 60))
            return Self.resolver.decide(before + [failing], tiers: tiers)
        }

        // Assert
        #expect(keptWhenFailingStarted.count == 7)
        for decision in decisions {
            #expect(decision.kept.subtracting(keptWhenFailingStarted).count == 1)
            #expect(decision.kept.isSuperset(of: keptWhenFailingStarted))
            #expect(decision.removals.allSatisfy { !keptWhenFailingStarted.contains($0.snapshot.id) })
        }
    }

    @Test("A failed run's partial goes once a newer snapshot completes, and stays while none has")
    func partials() {
        // Arrange
        let complete = Self.complete(Self.date(2026, 6, 1))
        let replaced = Self.partial(startedAt: Self.date(2026, 5, 31))
        let waiting = Self.partial(startedAt: Self.date(2026, 6, 2))

        // Act
        let decision = Self.resolver.decide([complete, replaced, waiting], tiers: RetentionTiers(dailySnapshots: 1, monthlySnapshots: 0))
        let noComplete = Self.resolver.decide([replaced, waiting], tiers: RetentionTiers(dailySnapshots: 1, monthlySnapshots: 0))

        // Assert
        #expect(decision.removals == [TierResolver.Removal(snapshot: replaced, reason: .replacedPartial)])
        #expect(decision.kept == [complete.id, waiting.id])
        #expect(noComplete.removals.isEmpty)
        #expect(noComplete.kept == [replaced.id, waiting.id])
    }

    @Test("The newest complete snapshot is never removed, and never offered to a quota")
    func newestKept() {
        // Arrange
        let snapshots = (1 ... 5).map { Self.date(2026, 6, $0) }.map(Self.complete)

        // Act
        let decision = Self.resolver.decide(snapshots, tiers: RetentionTiers(dailySnapshots: 1, monthlySnapshots: 0))

        // Assert
        #expect(decision.kept == [snapshots[4].id])
        #expect(decision.dailyOnly.isEmpty)
    }
}
