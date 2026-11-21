import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import ScoutProtocol
import Testing

struct ScoutEnrollmentTests {
    private let fixture: APIFixture
    private let server: Server
    private let stranger = ClientAddress(key: "203.0.113.9")

    init() async throws {
        fixture = try APIFixture()
        try fixture.setAddressOptions()
        server = try await fixture.addServer()
    }

    @Test("A Scout enrolls through its server's code without signing in, for that server, and can sign in")
    func enrolls() async throws {
        // Arrange
        let window = try await fixture.openEnrollmentWindow(for: server)
        let key = P256.Signing.PrivateKey()

        // Act
        let answer = try await fixture.sendEnrollment(fixture.enrollmentRequest(code: window.code, key: key))

        // Assert
        #expect(answer.status == .ok)
        let enrollment = try answer.decoded(as: ScoutEnrollment.self)
        #expect(enrollment.hiveID == fixture.signIn.hiveID)
        #expect(enrollment.serverID == server.id)
        let scout = try #require(try fixture.api.scouts.scout(forServer: server.id))
        #expect(scout.id == enrollment.scoutID)
        #expect(scout.publicKey == key.publicKey.x963Representation)
        #expect(scout.enrolledAt == fixture.signIn.clock.now)
        #expect(try await fixture.scoutToken(TestScout(enrollment: enrollment, key: key)).isEmpty == false)
    }

    @Test("The code carries the Hive ID, the server, the key pin, the address options and a token")
    func codeContents() async throws {
        // Act
        let window = try await fixture.openEnrollmentWindow(for: server)

        // Assert
        let code = try #require(EnrollmentCode(text: window.code))
        #expect(window.code.hasPrefix("scout1:"))
        #expect(code.hiveID == fixture.signIn.hiveID)
        #expect(code.serverID == server.id)
        #expect(code.pin == fixture.pin.sha256)
        #expect(code.addresses == [
            EnrollmentCode.Address(host: "studio.tail0000.ts.net", port: APIFixture.defaultPort),
            EnrollmentCode.Address(host: "hive.example.com", port: 44830),
        ])
        #expect(code.token.count == EnrollmentCode.tokenLength)
        #expect(window.serverID == server.id)
        #expect(window.expiresInSeconds == 15 * 60)
    }

    @Test("A token works once")
    func tokenWorksOnce() async throws {
        // Arrange
        let window = try await fixture.openEnrollmentWindow(for: server)
        let first = try await fixture.sendEnrollment(fixture.enrollmentRequest(code: window.code))
        let firstScout = try first.decoded(as: ScoutEnrollment.self)

        // Act
        let again = try await fixture.sendEnrollment(fixture.enrollmentRequest(code: window.code))

        // Assert
        #expect(again.status == .notFound)
        #expect(again.body.isEmpty)
        #expect(try fixture.api.scouts.scout(forServer: server.id)?.id == firstScout.scoutID)
    }

    @Test("A token never works after its window expires, and works just before")
    func expiredTokenRefused() async throws {
        // Arrange
        let expiring = try await fixture.openEnrollmentWindow(for: server)
        let other = try await fixture.addOtherServer()
        let lasting = try await fixture.openEnrollmentWindow(for: other)
        fixture.signIn.clock.advance(by: EnrollmentWindowStore.lifetime - 1)
        let justBefore = try await fixture.sendEnrollment(fixture.enrollmentRequest(code: lasting.code))
        fixture.signIn.clock.advance(by: 1)

        // Act
        let answer = try await fixture.sendEnrollment(fixture.enrollmentRequest(code: expiring.code))

        // Assert
        #expect(justBefore.status == .ok)
        #expect(answer.status == .notFound)
        #expect(try fixture.api.scouts.scout(forServer: server.id) == nil)
    }

    @Test("A token never works once its window is closed, and opening and closing are recorded")
    func closedWindowRefused() async throws {
        // Arrange
        let window = try await fixture.openEnrollmentWindow(for: server)
        let closed = try await fixture.send(.delete, HiveEndpoint.enrollmentWindow(forServer: server.id))

        // Act
        let answer = try await fixture.sendEnrollment(fixture.enrollmentRequest(code: window.code))

        // Assert
        #expect(closed.status == .noContent)
        #expect(answer.status == .notFound)
        #expect(try fixture.auditEvents().prefix(2) == [
            .scout(serverID: server.id, serverName: server.name, change: .enrollmentWindowClosed),
            .scout(serverID: server.id, serverName: server.name, change: .enrollmentWindowOpened),
        ])
    }

    @Test("Opening a new window for a server closes the one before, so its token stops working")
    func newWindowReplacesOld() async throws {
        // Arrange
        let first = try await fixture.openEnrollmentWindow(for: server)
        let second = try await fixture.openEnrollmentWindow(for: server)

        // Act
        let withFirst = try await fixture.sendEnrollment(fixture.enrollmentRequest(code: first.code))
        let withSecond = try await fixture.sendEnrollment(fixture.enrollmentRequest(code: second.code))

        // Assert
        #expect(withFirst.status == .notFound)
        #expect(withSecond.status == .ok)
    }

    @Test("Two servers' windows open at once both work, each for its own server, and neither closes a device's pairing window")
    func severalWindowsAtOnce() async throws {
        // Arrange
        let other = try await fixture.addOtherServer()
        let pairing = try await fixture.openPairingWindow()
        let forServer = try await fixture.openEnrollmentWindow(for: server)
        let forOther = try await fixture.openEnrollmentWindow(for: other)

        // Act
        let otherAnswer = try await fixture.sendEnrollment(fixture.enrollmentRequest(code: forOther.code))
        let serverAnswer = try await fixture.sendEnrollment(fixture.enrollmentRequest(code: forServer.code))
        let paired = try await fixture.sendPairing(fixture.pairingRequest(code: pairing.code))

        // Assert
        #expect(try otherAnswer.decoded(as: ScoutEnrollment.self).serverID == other.id)
        #expect(try serverAnswer.decoded(as: ScoutEnrollment.self).serverID == server.id)
        #expect(paired.status == .ok)
    }

    @Test("A device's token can't enroll a Scout, and leaves the pairing window open")
    func deviceTokenCantEnroll() async throws {
        // Arrange
        let pairing = try await fixture.openPairingWindow()
        _ = try await fixture.openEnrollmentWindow(for: server)
        let token = try #require(PairingCode(text: pairing.code)).token
        let request = ScoutEnrollmentRequest(
            token: token,
            scoutPublicKey: P256.Signing.PrivateKey().publicKey.x963Representation,
            protocolVersion: ScoutProtocolVersion.current
        )

        // Act
        let answer = try await fixture.sendEnrollment(request)

        // Assert
        #expect(answer.status == .notFound)
        #expect(try fixture.api.scouts.scout(forServer: server.id) == nil)
        #expect(try await fixture.sendPairing(fixture.pairingRequest(code: pairing.code)).status == .ok)
    }

    @Test("A Scout's token can't pair a device, and leaves the enrollment window open")
    func scoutTokenCantPair() async throws {
        // Arrange
        _ = try await fixture.openPairingWindow()
        let window = try await fixture.openEnrollmentWindow(for: server)
        let token = try #require(EnrollmentCode(text: window.code)).token
        let request = PairingRequest(
            token: token,
            devicePublicKey: P256.Signing.PrivateKey().publicKey.x963Representation,
            deviceName: "Intruder",
            apiVersions: .thisBuild
        )

        // Act
        let answer = try await fixture.sendPairing(request)

        // Assert
        #expect(answer.status == .notFound)
        #expect(try fixture.signIn.devices.all().count == 1)
        #expect(try await fixture.sendEnrollment(fixture.enrollmentRequest(code: window.code)).status == .ok)
    }

    @Test("Opening a window without confirmation is refused, and opens nothing")
    func openingNeedsConfirmation() async throws {
        // Arrange
        let before = try fixture.auditEvents()

        // Act
        let answer = try await fixture.send(.post, HiveEndpoint.enrollmentWindow(forServer: server.id))

        // Assert
        #expect(answer.status == .preconditionRequired)
        #expect(try answer.confirmationReasons == [.enrollmentWindowOpened])
        let anyToken = Data(count: EnrollmentCode.tokenLength)
        #expect(fixture.api.enrollmentWindows.check(anyToken, at: fixture.signIn.clock.now) == .noWindow)
        #expect(try fixture.auditEvents() == before)
    }

    @Test("A window can't be opened without an address option, nor for a server that isn't there")
    func refusedWithoutAddressOrServer() async throws {
        // Arrange
        let unknown = try await fixture.sendConfirmed(.post, HiveEndpoint.enrollmentWindow(forServer: UUID()))
        try fixture.setAddressOptions([])

        // Act
        let answer = try await fixture.sendConfirmed(.post, HiveEndpoint.enrollmentWindow(forServer: server.id))

        // Assert
        #expect(unknown.status == .notFound)
        #expect(answer.status == .unprocessableContent)
        #expect(try answer.decoded(as: EnrollmentWindowRefusal.self).problem == .noAddressOptions)
    }

    @Test("Enrolling is recorded as made by the device that opened the window")
    func enrollmentAudited() async throws {
        // Act
        _ = try await fixture.enrollScout(for: server)

        // Assert
        let entry = try #require(try fixture.auditLog.page(before: nil, limit: 1).entries.first)
        #expect(entry.event == .scout(serverID: server.id, serverName: server.name, change: .enrolled(replacedAnother: false)))
        #expect(entry.deviceID == fixture.signIn.device.id)
    }

    @Test("Enrolling again replaces the server's Scout: the old key can't sign in, and its session ends")
    func enrollingAgainReplaces() async throws {
        // Arrange
        let old = try await fixture.enrollScout(for: server)
        let oldToken = try await fixture.scoutToken(old)

        // Act
        let new = try await fixture.enrollScout(for: server)

        // Assert
        #expect(try await fixture.sendScoutSignIn(fixture.scoutSignInRequest(old)).status == .unauthorized)
        #expect(try await fixture.send(.get, ScoutEndpoint.session, token: oldToken).status == .unauthorized)
        #expect(try await fixture.send(.get, ScoutEndpoint.session, token: fixture.scoutToken(new)).status == .ok)
        let replaced = AuditEvent.scout(serverID: server.id, serverName: server.name, change: .enrolled(replacedAnother: true))
        #expect(try fixture.auditEvents().first == replaced)
    }

    @Test("A bad key is turned down without using up the token")
    func invalidKeyKeepsWindow() async throws {
        // Arrange
        let window = try await fixture.openEnrollmentWindow(for: server)
        let good = try fixture.enrollmentRequest(code: window.code)
        let badKey = ScoutEnrollmentRequest(
            token: good.token,
            scoutPublicKey: Data([4, 1, 2]),
            protocolVersion: ScoutProtocolVersion.current
        )

        // Act
        let withBadKey = try await fixture.sendEnrollment(badKey)
        let afterwards = try await fixture.sendEnrollment(good)

        // Assert
        #expect(withBadKey.status == .unprocessableContent)
        #expect(afterwards.status == .ok)
    }

    @Test("A Scout on a protocol Hive no longer accepts is told so, and the token is kept for an updated one")
    func oldProtocolRefused() async throws {
        // Arrange
        let window = try await fixture.openEnrollmentWindow(for: server)
        let tooOld = try fixture.enrollmentRequest(code: window.code, protocolVersion: ScoutProtocolVersion.current - 2)
        let previous = try fixture.enrollmentRequest(code: window.code, protocolVersion: ScoutProtocolVersion.current - 1)

        // Act
        let answer = try await fixture.sendEnrollment(tooOld)
        let afterwards = try await fixture.sendEnrollment(previous)

        // Assert
        #expect(answer.status == .conflict)
        #expect(try answer.decoded(as: ScoutProtocolMismatch.self).hiveProtocolVersion == ScoutProtocolVersion.current)
        #expect(afterwards.status == .ok)
    }

    @Test("A window opened by a device that's since been revoked can't be used")
    func revokedOpener() async throws {
        // Arrange
        let window = try await fixture.openEnrollmentWindow(for: server)
        _ = try fixture.api.revocation.revoke(fixture.signIn.device.id, by: fixture.signIn.device.id)

        // Act
        let answer = try await fixture.sendEnrollment(fixture.enrollmentRequest(code: window.code))

        // Assert
        #expect(answer.status == .notFound)
        #expect(try fixture.api.scouts.scout(forServer: server.id) == nil)
    }

    @Test("Wrong Scout tokens count toward the pairing endpoint's lockout, for devices too, and not for other addresses")
    func wrongTokensLockOut() async throws {
        // Arrange
        let window = try await fixture.openEnrollmentWindow(for: server)
        let pairing = try await fixture.openPairingWindow()
        let wrong = ScoutEnrollmentRequest(
            token: Data(repeating: 1, count: EnrollmentCode.tokenLength),
            scoutPublicKey: P256.Signing.PrivateKey().publicKey.x963Representation,
            protocolVersion: ScoutProtocolVersion.current
        )
        for _ in 0 ..< FailedAttemptPolicy.pairing.maximumFailures {
            #expect(fixture.api.scoutEnrollment.enroll(wrong, from: stranger) == .refused(.wrongToken))
        }

        // Act
        let scout = fixture.api.scoutEnrollment.enroll(try fixture.enrollmentRequest(code: window.code), from: stranger)
        let device = fixture.api.codePairing.pair(try fixture.pairingRequest(code: pairing.code), from: stranger)
        let elsewhere = fixture.api.scoutEnrollment.enroll(
            try fixture.enrollmentRequest(code: window.code),
            from: ClientAddress(key: "198.51.100.4")
        )

        // Assert
        #expect(scout == .lockedOut)
        #expect(device == .lockedOut)
        guard case .enrolled = elsewhere else {
            Issue.record("Another address was locked out too: \(elsewhere)")
            return
        }
    }
}
