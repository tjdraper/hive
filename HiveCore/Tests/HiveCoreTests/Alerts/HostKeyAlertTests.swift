import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

struct HostKeyAlertTests {
    private static let day: TimeInterval = 24 * 60 * 60

    @Test("A changed host key emails the old and new fingerprints and the last successful backup, not a failure for each job")
    func emailsFingerprints() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        try await fixture.succeedingRun()
        let newKey = SSHKeyPair().publicKey
        fixture.api.ssh.setScan(.found(newKey))
        let other = try await fixture.runs.addJob(named: "blog")

        // Act
        try fixture.recordRun(failing: .hostKeyChanged)
        try fixture.recordRun(failing: .hostKeyChanged, job: other)
        await fixture.check()

        // Assert
        let sent = try fixture.sent()
        #expect(sent.map(\.subject) == ["Host key changed: “Studio Web”"])
        let body = try #require(sent.first?.body)
        #expect(body.contains(ConfigurationSamples.hostKey.fingerprint))
        #expect(body.contains(newKey.fingerprint))
        #expect(!body.contains("Last successful backup: none yet"))
        #expect(fixture.api.ssh.scanned.count == 2)
    }

    @Test("It's sent again each day until the new key is confirmed, then stops")
    func remindsUntilConfirmed() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        let newKey = SSHKeyPair().publicKey
        fixture.api.ssh.setScan(.found(newKey))
        try fixture.recordRun(failing: .hostKeyChanged)
        await fixture.check()

        // Act
        fixture.clock.advance(by: Self.day)
        try fixture.recordRun(failing: .hostKeyChanged)
        await fixture.check()
        let server = fixture.runs.serverRecord
        _ = try await fixture.api.send(.post, HiveEndpoint.hostKeyScan(onServer: server.id))
        let confirmation = HostKeyConfirmation(fingerprint: newKey.fingerprint)
        let answer = try await fixture.api.sendConfirmed(.put, HiveEndpoint.hostKey(onServer: server.id), json: confirmation)
        #expect(answer.status == .ok)
        await fixture.check()
        fixture.clock.advance(by: Self.day)
        await fixture.check()

        // Assert
        let subjects = try fixture.sent().map(\.subject).filter { $0.contains("host key") || $0.contains("Host key") }
        #expect(subjects == ["Host key changed: “Studio Web”", "Still refusing “Studio Web”'s changed host key"])
    }

    @Test("When the original key comes back, a run that gets past it ends the alert without another email")
    func originalKeyBack() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        try fixture.recordRun(failing: .hostKeyChanged)
        await fixture.check()

        // Act
        try fixture.recordRun(failing: .databaseLoginRefused)
        await fixture.check()
        fixture.clock.advance(by: Self.day)
        await fixture.check()

        // Assert
        #expect(try fixture.sent(startingWith: "Host key").count == 1)
        #expect(try fixture.sent(startingWith: "Still refusing").isEmpty)
        #expect(try fixture.store.all().allSatisfy { $0.facts.condition != .hostKeyChanged(serverID: fixture.runs.serverRecord.id) })
    }

    @Test("A run that fails before reaching the server leaves the alert open")
    func unreachableKeepsAlert() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        try fixture.recordRun(failing: .hostKeyChanged)
        await fixture.check()

        // Act
        try fixture.recordRun(failing: .unreachable)
        fixture.clock.advance(by: Self.day)
        await fixture.check()

        // Assert
        #expect(try fixture.sent(startingWith: "Still refusing").count == 1)
    }

    @Test("A key Hive couldn't scan is given as unknown")
    func unscannedKey() async throws {
        // Arrange
        let fixture = try await AlertFixture()
        fixture.api.ssh.setScan(.failed(.unreachable))

        // Act
        try fixture.recordRun(failing: .hostKeyChanged)
        await fixture.check()

        // Assert
        #expect(try #require(try fixture.sent(startingWith: "Host key").first).body.contains("Key it sent:   unknown"))
    }
}
