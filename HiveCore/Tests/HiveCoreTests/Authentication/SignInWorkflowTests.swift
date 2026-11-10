import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Testing

struct SignInWorkflowTests {
    private let fixture: SignInFixture
    private let address = ClientAddress(key: "192.0.2.1")

    init() throws {
        fixture = try SignInFixture()
    }

    @Test("A valid signature over a fresh challenge signs in, and the session belongs to that device")
    func validSignatureSignsIn() throws {
        // Arrange
        let request = try fixture.request()

        // Act
        let outcome = fixture.workflow.signIn(request, from: address)

        // Assert
        let token = try #require(outcome.token)
        #expect(fixture.sessions.deviceID(forToken: token, at: fixture.clock.now) == fixture.device.id)
    }

    @Test("Signing in records when the device was last seen")
    func signInRecordsLastSeen() throws {
        // Arrange
        fixture.clock.advance(by: 60)
        let request = try fixture.request()

        // Act
        _ = fixture.workflow.signIn(request, from: address)

        // Assert
        let device = try #require(try fixture.devices.device(id: fixture.device.id))
        #expect(device.lastSeenAt == fixture.clock.now)
    }

    @Test("A signature replayed after it signed in is refused")
    func replayedSignatureIsRefused() throws {
        // Arrange
        let request = try fixture.request()
        _ = fixture.workflow.signIn(request, from: address)

        // Act
        let outcome = fixture.workflow.signIn(request, from: address)

        // Assert
        #expect(outcome == .refused(.challengeReused))
    }

    @Test("A signature over an expired challenge is refused")
    func expiredChallengeIsRefused() throws {
        // Arrange
        let request = try fixture.request()
        fixture.clock.advance(by: SignInWorkflow.challengeLifetime + 1)

        // Act
        let outcome = fixture.workflow.signIn(request, from: address)

        // Assert
        #expect(outcome == .refused(.challengeExpired))
    }

    @Test("A challenge Hive didn't issue is refused, even when properly signed")
    func madeUpChallengeIsRefused() throws {
        // Arrange
        var challenge = fixture.workflow.issueChallenge().challenge
        challenge[challenge.startIndex + 10] ^= 0xFF
        let request = try fixture.request(challenge: challenge)

        // Act
        let outcome = fixture.workflow.signIn(request, from: address)

        // Assert
        #expect(outcome == .refused(.challengeNotIssued))
    }

    @Test("A challenge issued by another Hive, or before this one restarted, is refused")
    func otherHivesChallengeIsRefused() throws {
        // Arrange
        let other = try SignInFixture()
        let request = try fixture.request(challenge: other.workflow.issueChallenge().challenge)

        // Act
        let outcome = fixture.workflow.signIn(request, from: address)

        // Assert
        #expect(outcome == .refused(.challengeNotIssued))
    }

    @Test("A signature by another key is refused")
    func otherKeyIsRefused() throws {
        // Arrange
        let request = try fixture.request(key: P256.Signing.PrivateKey())

        // Act
        let outcome = fixture.workflow.signIn(request, from: address)

        // Assert
        #expect(outcome == .refused(.badSignature))
    }

    @Test("A signature for one challenge doesn't sign in with another")
    func signatureForAnotherChallengeIsRefused() throws {
        // Arrange
        let signed = try fixture.request()
        let request = SignInRequest(
            deviceID: signed.deviceID,
            challenge: fixture.workflow.issueChallenge().challenge,
            signature: signed.signature,
            apiVersions: signed.apiVersions
        )

        // Act
        let outcome = fixture.workflow.signIn(request, from: address)

        // Assert
        #expect(outcome == .refused(.badSignature))
    }

    @Test("A failed signature leaves the challenge unused, and doesn't stop the device signing in with it")
    func failedSignatureDoesNotUseChallenge() throws {
        // Arrange
        let challenge = fixture.workflow.issueChallenge().challenge
        _ = fixture.workflow.signIn(try fixture.request(key: P256.Signing.PrivateKey(), challenge: challenge), from: address)

        // Act
        let outcome = fixture.workflow.signIn(try fixture.request(challenge: challenge), from: address)

        // Assert
        #expect(outcome.token != nil)
    }

    @Test("A device Hive doesn't know is refused")
    func unknownDeviceIsRefused() throws {
        // Arrange
        let request = try fixture.request(deviceID: UUID())

        // Act
        let outcome = fixture.workflow.signIn(request, from: address)

        // Assert
        #expect(outcome == .refused(.unknownDevice))
    }

    @Test("A revoked device's key can't sign in")
    func revokedDeviceIsRefused() throws {
        // Arrange
        _ = try fixture.devices.remove(id: fixture.device.id, by: fixture.device.id, at: fixture.clock.now)
        let request = try fixture.request()

        // Act
        let outcome = fixture.workflow.signIn(request, from: address)

        // Assert
        #expect(outcome == .refused(.unknownDevice))
    }

    @Test("A body that isn't a sign-in request is refused")
    func malformedRequestIsRefused() {
        // Act
        let outcome = fixture.workflow.signIn(nil, from: address)

        // Assert
        #expect(outcome == .refused(.malformed))
    }

    @Test("A Beekeeper too old for this Hive is told to update, and gets no session")
    func oldBeekeeperIsTurnedAway() throws {
        // Arrange
        let fixture = try SignInFixture(apiVersions: APIVersions(current: 3, oldestCompatible: 2))
        let request = try fixture.request(apiVersions: APIVersions(current: 1, oldestCompatible: 1))

        // Act
        let outcome = fixture.workflow.signIn(request, from: address)

        // Assert
        #expect(outcome == .incompatible(.beekeeper))
    }

    @Test("A Beekeeper newer than this Hive understands is told to update Hive")
    func oldHiveIsReported() throws {
        // Arrange
        let request = try fixture.request(apiVersions: APIVersions(current: 5, oldestCompatible: 4))

        // Act
        let outcome = fixture.workflow.signIn(request, from: address)

        // Assert
        #expect(outcome == .incompatible(.hive))
    }

    @Test("A session token stops working when it expires")
    func sessionExpires() throws {
        // Arrange
        let token = try #require(fixture.workflow.signIn(try fixture.request(), from: address).token)
        fixture.clock.advance(by: SessionStore.lifetime - 1)
        #expect(fixture.sessions.deviceID(forToken: token, at: fixture.clock.now) == fixture.device.id)

        // Act
        fixture.clock.advance(by: 1)

        // Assert
        #expect(fixture.sessions.deviceID(forToken: token, at: fixture.clock.now) == nil)
    }

    @Test("Ending a device's sessions stops its tokens at once, and leaves other devices' alone")
    func endingSessionsStopsTokens() throws {
        // Arrange
        let token = try #require(fixture.workflow.signIn(try fixture.request(), from: address).token)
        let other = fixture.sessions.start(for: UUID(), at: fixture.clock.now)

        // Act
        fixture.sessions.endSessions(for: fixture.device.id)

        // Assert
        #expect(fixture.sessions.deviceID(forToken: token, at: fixture.clock.now) == nil)
        #expect(fixture.sessions.deviceID(forToken: other.token, at: fixture.clock.now) != nil)
    }
}
