import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

/// A lower quota or lower tiers deletes snapshots, so neither is saved, and nothing is removed, until
/// a device confirms it (§10). Before that, Hive says how many it would remove.
struct UnconfirmedLoweringTests {
    /// Seven snapshots a day apart, each with a file of its own.
    private static func weekOfSnapshots() async throws -> (BackupRunFixture, [SnapshotRecord]) {
        let fixture = try await BackupRunFixture()
        let snapshots = try await fixture.runDaysApart([1, 1, 1, 1, 1, 1, 1])
        // Counts what each frees, as the pass after each run would have for all but the newest.
        await fixture.retentionPass()
        return (fixture, snapshots)
    }

    @Test("Lowering a quota without confirmation removes nothing")
    func unconfirmedQuota() async throws {
        // Arrange
        let (fixture, snapshots) = try await Self.weekOfSnapshots()
        var draft = fixture.serverRecord.draft
        draft.quotaBytes = 1

        // Act
        let answer = try await fixture.api.send(.put, HiveEndpoint.server(fixture.serverRecord.id), json: draft)
        await fixture.retentionPass()

        // Assert
        #expect(answer.status == .preconditionRequired)
        #expect(try answer.confirmationReasons == [.quotaLowered])
        #expect(try fixture.api.servers.server(id: fixture.serverRecord.id)?.quotaBytes == fixture.serverRecord.quotaBytes)
        #expect(try fixture.completeSnapshots().map(\.id) == snapshots.map(\.id))
        #expect(snapshots.allSatisfy { FileManager.default.fileExists(atPath: fixture.snapshotURL($0).fileSystemPath) })
        #expect(try await fixture.removals().isEmpty)
    }

    @Test("Lowering a job's tiers without confirmation removes nothing")
    func unconfirmedTiers() async throws {
        // Arrange
        let (fixture, snapshots) = try await Self.weekOfSnapshots()
        var draft = fixture.job.draft
        draft.retention = RetentionTiers(dailySnapshots: 1, monthlySnapshots: 0)

        // Act
        let answer = try await fixture.api.send(.put, HiveEndpoint.job(fixture.job.id), json: draft)
        await fixture.retentionPass()

        // Assert
        #expect(answer.status == .preconditionRequired)
        #expect(try answer.confirmationReasons == [.retentionLowered])
        #expect(try fixture.completeSnapshots().map(\.id) == snapshots.map(\.id))
        #expect(try await fixture.removals().isEmpty)
    }

    @Test("A lower quota's estimate counts the oldest daily snapshots it takes to fit, and the pass removes no more")
    func quotaEstimate() async throws {
        // Arrange
        let (fixture, _) = try await Self.weekOfSnapshots()
        let used = try #require(try fixture.usedBytes())
        let path = HiveEndpoint.quotaEstimate(ofServer: fixture.serverRecord.id)

        // Act
        let none = try await fixture.api.send(.post, path, json: QuotaEstimateRequest(quotaBytes: used))
        let some = try await fixture.api.send(.post, path, json: QuotaEstimateRequest(quotaBytes: used - 1))
            .decoded(as: RemovalEstimate.self)
        let all = try await fixture.api.send(.post, path, json: QuotaEstimateRequest(quotaBytes: 1)).decoded(as: RemovalEstimate.self)
        try await fixture.setQuota(used - 1)
        await fixture.retentionPass()

        // Assert
        #expect(try none.decoded(as: RemovalEstimate.self).snapshotCount == 0)
        #expect(some.snapshotCount == 1)
        // The newest is never removed to meet a quota.
        #expect(all.snapshotCount == 6)
        let removed = try await fixture.removals().flatMap(\.removed)
        #expect(removed.count <= some.snapshotCount ?? 0)
    }

    @Test("Lower tiers' estimate counts what they'd no longer keep, and the pass removes exactly that")
    func tiersEstimate() async throws {
        // Arrange
        let (fixture, _) = try await Self.weekOfSnapshots()
        let path = HiveEndpoint.retentionEstimate(ofJob: fixture.job.id)
        let lower = RetentionTiers(dailySnapshots: 3, monthlySnapshots: 0)

        // Act
        let same = try await fixture.api.send(.post, path, json: fixture.job.retention).decoded(as: RemovalEstimate.self)
        let estimate = try await fixture.api.send(.post, path, json: lower).decoded(as: RemovalEstimate.self)
        try await fixture.setTiers(daily: lower.dailySnapshots, monthly: lower.monthlySnapshots)
        await fixture.retentionPass()

        // Assert
        #expect(same.snapshotCount == 0)
        #expect(estimate.snapshotCount == 4)
        #expect(try await fixture.removals().flatMap(\.removed).count == 4)
    }

    @Test("A quota's estimate isn't known until the server's snapshots are counted")
    func uncountedEstimate() async throws {
        // Arrange
        let (fixture, _) = try await Self.weekOfSnapshots()
        try await fixture.database.writer.write { try $0.execute(sql: "UPDATE jobSpace SET usedBytes = NULL") }

        // Act
        let path = HiveEndpoint.quotaEstimate(ofServer: fixture.serverRecord.id)
        let estimate = try await fixture.api.send(.post, path, json: QuotaEstimateRequest(quotaBytes: 1))

        // Assert
        #expect(try estimate.decoded(as: RemovalEstimate.self).snapshotCount == nil)
    }
}
