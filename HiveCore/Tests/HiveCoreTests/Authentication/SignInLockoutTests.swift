import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct SignInLockoutTests {
    private let fixture: SignInFixture
    private let attacker = ClientAddress(key: "203.0.113.9")
    private let elsewhere = ClientAddress(key: "198.51.100.4")
    private let maximumFailures = FailedAttemptPolicy.signIn.maximumFailures

    init() throws {
        fixture = try SignInFixture()
    }

    private func failFromAttacker(times: Int) throws {
        for _ in 0 ..< times {
            _ = fixture.workflow.signIn(try fixture.request(deviceID: UUID()), from: attacker)
        }
    }

    @Test("Repeated failures from one address lock out that address, even with a valid signature")
    func failuresLockOutAddress() throws {
        // Arrange
        try failFromAttacker(times: maximumFailures)

        // Act
        let outcome = fixture.workflow.signIn(try fixture.request(), from: attacker)

        // Assert
        #expect(outcome == .lockedOut)
    }

    @Test("One fewer failure than the limit doesn't lock out")
    func fewerFailuresDoNotLockOut() throws {
        // Arrange
        try failFromAttacker(times: maximumFailures - 1)

        // Act
        let outcome = fixture.workflow.signIn(try fixture.request(), from: attacker)

        // Assert
        #expect(outcome.token != nil)
    }

    @Test("A locked-out address doesn't lock out any other address")
    func lockoutIsPerAddress() throws {
        // Arrange
        try failFromAttacker(times: maximumFailures)

        // Act
        let outcome = fixture.workflow.signIn(try fixture.request(), from: elsewhere)

        // Assert
        #expect(outcome.token != nil)
    }

    @Test("The lockout ends")
    func lockoutEnds() throws {
        // Arrange
        try failFromAttacker(times: maximumFailures)
        fixture.clock.advance(by: FailedAttemptPolicy.signIn.lockout)

        // Act
        let outcome = fixture.workflow.signIn(try fixture.request(), from: attacker)

        // Assert
        #expect(outcome.token != nil)
    }

    @Test("Failures spread wider than the window don't add up to a lockout")
    func oldFailuresAreForgotten() throws {
        // Arrange
        try failFromAttacker(times: maximumFailures - 1)
        fixture.clock.advance(by: FailedAttemptPolicy.signIn.window)
        try failFromAttacker(times: 1)

        // Act
        let outcome = fixture.workflow.signIn(try fixture.request(), from: attacker)

        // Assert
        #expect(outcome.token != nil)
    }

    @Test("Bad signatures for one device from many addresses lock out that device, and not others")
    func failuresLockOutDevice() throws {
        // Arrange
        for index in 0 ..< maximumFailures {
            let wrongKey = try fixture.request(key: P256.Signing.PrivateKey())
            _ = fixture.workflow.signIn(wrongKey, from: ClientAddress(key: "203.0.113.\(index)"))
        }
        let otherKey = P256.Signing.PrivateKey()
        let otherDevice = try fixture.devices.add(
            name: "Other",
            publicKey: otherKey.publicKey.x963Representation,
            at: fixture.clock.now,
            auditedAs: .pairedOnHiveMac
        )

        // Act
        let lockedOut = fixture.workflow.signIn(try fixture.request(), from: elsewhere)
        let other = fixture.workflow.signIn(try fixture.request(key: otherKey, deviceID: otherDevice.id), from: elsewhere)

        // Assert
        #expect(lockedOut == .lockedOut)
        #expect(other.token != nil)
    }

    @Test("Signing in clears the failures counted against the address")
    func signInClearsFailures() throws {
        // Arrange
        try failFromAttacker(times: maximumFailures - 1)
        _ = fixture.workflow.signIn(try fixture.request(), from: attacker)
        try failFromAttacker(times: maximumFailures - 1)

        // Act
        let outcome = fixture.workflow.signIn(try fixture.request(), from: attacker)

        // Assert
        #expect(outcome.token != nil)
    }

    @Test("Past the number of addresses it tracks, the limiter forgets the oldest, keeping memory bounded")
    func limiterForgetsOldest() {
        // Arrange
        let policy = FailedAttemptPolicy(maximumFailures: 1, window: 60, lockout: 60, maximumTracked: 2)
        let limiter = FailedAttemptLimiter<String>(policy: policy)
        let start = Date(timeIntervalSince1970: 0)
        limiter.recordFailure("first", at: start)
        limiter.recordFailure("second", at: start + 1)

        // Act
        limiter.recordFailure("third", at: start + 2)

        // Assert
        #expect(!limiter.isLockedOut("first", at: start + 3))
        #expect(limiter.isLockedOut("second", at: start + 3))
        #expect(limiter.isLockedOut("third", at: start + 3))
    }
}
