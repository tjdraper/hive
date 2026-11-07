import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

/// The fixture's clock starts on 15 January, in New York's time zone.
struct QuotaTests {
    /// Snapshots on 16 January, 25 February and 17–21 March, with a run on 5 February that the tiers
    /// remove. The tiers keep the last five days and three months: 16 January and 25 February as
    /// monthly, 21 March as newest and monthly, and 17–20 March as daily alone.
    private static func monthsOfSnapshots() async throws -> (BackupRunFixture, [SnapshotRecord]) {
        let fixture = try await BackupRunFixture()
        try fixture.write(String(repeating: "shared ", count: 30_000), to: "srv/site/big.txt")
        try await fixture.setTiers(daily: 5, monthly: 3)
        let snapshots = try await fixture.runDaysApart([1, 20, 20, 20, 1, 1, 1, 1])
        return (fixture, snapshots)
    }

    @Test("Over quota, the oldest daily snapshots go first, until the server fits")
    func oldestDailyFirst() async throws {
        // Arrange
        let (fixture, snapshots) = try await Self.monthsOfSnapshots()
        #expect(snapshots.count == 7)
        let used = try #require(try fixture.usedBytes())

        // Act
        try await fixture.setQuota(used - 1)
        await fixture.retentionPass()

        // Assert
        let left = try fixture.completeSnapshots()
        #expect(left.map(\.id) == snapshots.filter { $0.id != snapshots[2].id }.map(\.id))
        let removed = try await fixture.removals().flatMap(\.removed).filter { $0.reason == .quota }
        #expect(removed.map(\.snapshotID) == [snapshots[2].id])
        #expect(try fixture.usedBytes() ?? .max <= used - 1)
        #expect(try fixture.overQuota().isEmpty)
    }

    @Test("A quota never removes a monthly snapshot or the newest, and marks the server over quota when that's all that's left")
    func monthlyAndNewestStay() async throws {
        // Arrange
        let (fixture, snapshots) = try await Self.monthsOfSnapshots()
        let before = try fixture.snapshotBlocks()

        // Act
        try await fixture.setQuota(1)
        await fixture.retentionPass()

        // Assert
        let left = try fixture.completeSnapshots()
        #expect(left.map(\.id) == [snapshots[0].id, snapshots[1].id, snapshots[6].id])
        let removed = try await fixture.removals().flatMap(\.removed).filter { $0.reason == .quota }
        #expect(removed.map(\.snapshotID) == snapshots[2 ... 5].map(\.id))
        #expect(removed.reduce(0) { $0 + $1.bytesFreed } == DriveUsage.freed(from: before, to: try fixture.snapshotBlocks()))
        #expect(try fixture.overQuota()[fixture.serverRecord.id] == fixture.clock.now)
    }

    @Test("A server back within its quota, or with none, is no longer marked over it")
    func overQuotaCleared() async throws {
        // Arrange
        let (fixture, _) = try await Self.monthsOfSnapshots()
        try await fixture.setQuota(1)
        await fixture.retentionPass()
        let since = try #require(try fixture.overQuota()[fixture.serverRecord.id])

        // Act
        fixture.clock.advance(by: 60)
        await fixture.retentionPass()
        let stillOver = try fixture.overQuota()[fixture.serverRecord.id]
        try await fixture.setQuota(nil)
        await fixture.retentionPass()

        // Assert
        #expect(stillOver == since)
        #expect(try fixture.overQuota().isEmpty)
    }

    @Test("A quota takes the oldest daily snapshot across all of the server's jobs")
    func acrossJobs() async throws {
        // Arrange
        let fixture = try await BackupRunFixture()
        let other = try await fixture.addJob(named: "other")
        let first = try await fixture.runDaysApart([1, 1, 1])
        let second = try await fixture.runDaysApart([0, 1], job: other, source: "srv/other")
        let used = try #require(try fixture.usedBytes())
        let otherUsed = try #require(try fixture.usedBytes(of: other))

        // Act
        try await fixture.setQuota(used + otherUsed - 1)
        await fixture.retentionPass()

        // Assert
        let removed = try await fixture.removals().flatMap(\.removed)
        #expect(removed.map(\.snapshotID) == [first[0].id])
        #expect(try fixture.completeSnapshots(of: other).map(\.id) == second.map(\.id))
    }
}
