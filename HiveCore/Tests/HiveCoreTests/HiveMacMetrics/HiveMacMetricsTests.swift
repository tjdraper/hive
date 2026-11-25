import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import ScoutCore
import ScoutProtocol
import Testing

struct HiveMacMetricsTests {
    private static func workflow(_ fixture: APIFixture) -> HiveMacMetricsWorkflow {
        fixture.api.hiveMacSampler.workflow
    }

    private static func turn(_ isOn: Bool, on fixture: APIFixture) async throws {
        var settings = try fixture.settings.settings()
        settings.collectsMacMetrics = isOn
        let answer = try await fixture.send(.put, HiveEndpoint.settings, json: settings)
        #expect(answer.status == .ok)
    }

    private static func keptSampleTimes(_ fixture: APIFixture) throws -> [Int64] {
        try fixture.metricsDatabase.writer.read { database in
            try Int64.fetchAll(database, sql: """
            SELECT startsAt FROM serverTenSeconds JOIN metricsServer ON metricsServer.id = serverKey
            WHERE metricsServer.serverID = ? ORDER BY startsAt
            """, arguments: [fixture.signIn.hiveID])
        }
    }

    @Test("The Hive Mac's figures are kept under the Hive's own ID, and it comes first on the dashboard")
    func keptAndShown() async throws {
        // Arrange
        let fixture = try APIFixture()
        try fixture.setAddressOptions()
        let server = try await fixture.addServer()
        _ = try await fixture.enrollScout(for: server)
        let now = Int64(fixture.signIn.clock.now.timeIntervalSince1970)

        // Act
        Self.workflow(fixture).keep(TestMetrics.sample(at: now))

        // Assert
        let summaries = try fixture.api.metricsSummaries.summaries()
        #expect(summaries.map(\.serverID) == [fixture.signIn.hiveID, server.id])
        #expect(summaries.first?.reporting == .reporting)
        #expect(summaries.first?.latest?.takenAt == now)
        let state = try #require(try fixture.api.metricsState.state(ofServer: fixture.signIn.hiveID))
        #expect(state.hasMetrics)
        #expect(state.scout?.distribution == "Debian GNU/Linux 12 (bookworm)")
        let series = try await fixture.send(
            .get, HiveEndpoint.metricsSeries(ofServer: fixture.signIn.hiveID, from: now - 60, to: now + 60, figures: [.cpuUser])
        )
        #expect(series.status == .ok)
    }

    @Test("Turning it off stops sampling and keeps the history, which still charts")
    func turningOff() async throws {
        // Arrange: this Mac's own figures, read by Scout's readers.
        let fixture = try APIFixture()
        let sampler = fixture.api.hiveMacSampler
        let start = Int64(fixture.signIn.clock.now.timeIntervalSince1970) / 10 * 10
        var macSampler: MacSampler?
        await sampler.step(at: start, sampler: &macSampler)
        await sampler.step(at: start + 10, sampler: &macSampler)

        // Act
        try await Self.turn(false, on: fixture)
        await sampler.step(at: start + 20, sampler: &macSampler)
        fixture.api.metricsUpkeep.runOnce()

        // Assert
        #expect(try Self.keptSampleTimes(fixture) == [start, start + 10])
        #expect(macSampler == nil)
        #expect(try fixture.api.metricsSummaries.summaries().isEmpty)
        #expect(try fixture.api.metricsState.state(ofServer: fixture.signIn.hiveID)?.hasMetrics == false)
        let series = try await fixture.send(
            .get, HiveEndpoint.metricsSeries(ofServer: fixture.signIn.hiveID, from: start - 60, to: start + 60, figures: [.cpuUser])
        )
        #expect(series.status == .ok)
        #expect(try fixture.auditEvents().first == .macMetricsChanged(isOn: false))
    }

    @Test("A sample of this Mac has its figures, with no I/O wait, steal, pressure, containers or services")
    func realSample() async throws {
        // Arrange
        var sampler = MacSampler()
        _ = await sampler.sample(takenAt: 0)

        // Act
        let sample = await sampler.sample(takenAt: 10)

        // Assert
        let use = try #require(sample.cpu?.use)
        #expect(use.ioWait == nil && use.steal == nil)
        #expect(sample.pressure == nil && sample.containers == nil && sample.services == nil)
        #expect(sample.filesystems.contains { $0.mountPoint == "/" })
        #expect(sample.memory.map { $0.availableBytes < $0.totalBytes } == true)
        #expect(sample.processes.map { !$0.groups.isEmpty } == true)
        #expect(sample.server.distribution?.hasPrefix("macOS ") == true)
        // Not root, so other users' processes are only counted.
        #expect(getuid() == 0 || sample.processes?.otherUsers.map { $0.count >= 1 } == true)
    }

    @Test("Other users' processes are kept, and come back with a moment's processes")
    func otherUsers() throws {
        // Arrange
        let fixture = try APIFixture()
        let now = Int64(fixture.signIn.clock.now.timeIntervalSince1970) / 10 * 10
        var sample = TestMetrics.sample(at: now)
        sample.processes?.otherUsers = OtherUsersProcesses(count: 228, cpuCores: 0.3)

        // Act
        Self.workflow(fixture).keep(sample)

        // Assert
        let moment = try fixture.api.processMoments.processes(ofServer: fixture.signIn.hiveID, at: now)
        guard case .sample(_, _, let otherUsers) = moment else {
            Issue.record("Expected the sample, got \(moment)")
            return
        }
        #expect(otherUsers == OtherUsersProcessFigures(count: 228, cpuCores: 0.3))
    }

    @Test("The backup drive's volumes are left out of the Mac's disk alerts, and other volumes aren't")
    func backupDriveLeftOut() {
        // Arrange: the drive is `/Volumes/Hive`, which shares its APFS container with `/Volumes/ivy-ext-01`.
        let filesystem = { (mountPoint: String, device: String) in
            FilesystemFigures(mountPoint: mountPoint, device: device, type: "apfs", space: nil)
        }
        let filesystems = [
            filesystem("/", "/dev/disk3s1s1"),
            filesystem("/Volumes/Hive", "/dev/disk7s2"),
            filesystem("/Volumes/ivy-ext-01", "/dev/disk7s1"),
            filesystem("/Volumes/ivy-ext-02", "/dev/disk9s1"),
            filesystem("/Volumes/disk70", "/dev/disk70s1"),
        ]

        // Act
        let checked = HiveMacMetricsWorkflow.leavingOutBackupDrive(filesystems, mountPoint: "/Volumes/Hive")

        // Assert
        #expect(checked.map(\.mountPoint) == ["/", "/Volumes/ivy-ext-02", "/Volumes/disk70"])
    }

    @Test("A full backup drive sends no disk email of the Mac's, while a full startup disk does, naming the Hive Mac")
    func backupDriveEmail() async throws {
        // Arrange
        let alerts = try await MetricAlertFixture()
        let fixture = alerts.api
        let drive = try TemporaryDirectory()
        let volume = BackupRunFixture.volume(at: drive.url)
        fixture.volumes.set([volume])
        try await fixture.signIn.database.writer.write { database in
            try database.execute(sql: "UPDATE hive SET backupDriveUUID = ?", arguments: [volume.uuid.uuidString])
        }
        let hiveName = try fixture.settings.settings().name
        var sample = alerts.sample()
        sample.filesystems = [
            TestMetrics.filesystem("/", available: 2_000_000_000),
            TestMetrics.filesystem(drive.url.fileSystemPath, available: 1_000_000_000),
        ]

        // Act
        Self.workflow(fixture).keep(sample)
        await alerts.check()

        // Assert
        #expect(try alerts.subjects() == ["Disk filling up: “/” on the Hive Mac “\(hiveName)”"])
        let summary = try fixture.api.metricsSummaries.summaries().first { $0.serverID == fixture.signIn.hiveID }
        #expect(summary?.alerts == [.filesystemFilling(mountPoint: "/")])
    }
}
