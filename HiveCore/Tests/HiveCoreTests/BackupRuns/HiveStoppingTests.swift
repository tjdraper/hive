import Darwin
import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct HiveStoppingTests {
    @Test("A child process stays in Hive's process group, so launchd stops it when Hive exits, even by crashing")
    func childInHivesProcessGroup() async throws {
        // Arrange
        let exited = AsyncStream.makeStream(of: Int32.self)

        // Act
        let child = try SpawnedProcess(
            executable: URL(filePath: "/bin/sleep"),
            arguments: ["30"],
            environment: [:],
            standardInput: FileHandle.nullDevice.fileDescriptor,
            standardOutput: FileHandle.nullDevice.fileDescriptor,
            standardError: FileHandle.nullDevice.fileDescriptor
        ) { status in
            exited.continuation.yield(status)
            exited.continuation.finish()
        }
        let group = getpgid(child.processIdentifier)
        child.signal(SIGTERM)
        var statuses = exited.stream.makeAsyncIterator()
        let status = await statuses.next()

        // Assert
        #expect(group == getpgrp())
        #expect(status == SIGTERM)
        #expect(!child.isRunning)
    }

    @Test("Stopping Hive stops the run going now and starts nothing more, and the next start marks it interrupted and runs it")
    func stoppingLeavesRunForNextStart() async throws {
        // Arrange
        let fixture = try await BackupRunFixture.withDatabase()
        let other = try await fixture.addJob(named: "Other")
        fixture.databaseServer.hold()
        _ = try await fixture.runNow()
        try await fixture.waitUntilRunning(BackupRunFixture.dumping)
        _ = try await fixture.runNow(other)

        // Act
        await fixture.runs.stop()
        let afterStopping = try await fixture.jobLog().entries
        fixture.databaseServer.release()
        let restarted = try APIFixture(
            signIn: fixture.api.signIn,
            sealer: fixture.api.sealer,
            dumpSearchPath: fixture.databaseServer.searchPath
        )
        restarted.volumes.set(fixture.api.volumes.current)
        try await restarted.api.runs.start()
        await restarted.api.runs.waitUntilIdle()

        // Assert
        #expect(afterStopping.count == 1)
        #expect(afterStopping.first?.run.finishedAt == nil)
        let entries = try await fixture.jobLog().entries
        // Run Now still goes first.
        #expect(entries.map(\.jobName) == [fixture.job.name, "Other", fixture.job.name])
        #expect(entries.map(\.trigger) == [.afterInterruption, .runNow, .runNow])
        #expect(entries.last?.run.failure == .interrupted)
        #expect(entries.dropLast().map(\.run.failure) == [nil, nil])
        #expect(entries.first?.run.pickedUpPartialSnapshot == true)
    }
}
