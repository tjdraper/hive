import CryptoKit
import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

extension APIFixture {
    static let addressOptions = [AddressOption(host: "studio.tail0000.ts.net"), AddressOption(host: "hive.example.com", port: 44830)]

    /// Straight into the store, so tests' audit logs start with only what they do.
    func setAddressOptions(_ options: [AddressOption] = addressOptions) throws {
        let stored = try HiveSettingsStore.stored(options)
        try signIn.database.writer.write { database in
            try database.execute(sql: "UPDATE hive SET addressOptions = ?", arguments: [stored])
        }
    }

    func openPairingWindow() async throws -> PairingWindow {
        let answer = try await sendConfirmed(.post, HiveEndpoint.pairingWindow)
        guard answer.status == .created else { throw APIFixtureError.unexpectedStatus(answer.status) }
        return try answer.decoded(as: PairingWindow.self)
    }

    func pairingRequest(
        code: String,
        key: P256.Signing.PrivateKey = P256.Signing.PrivateKey(),
        name: String = "Everyday Mac",
        apiVersions: APIVersions = .thisBuild
    ) throws -> PairingRequest {
        let token = try #require(PairingCode(text: code)).token
        return PairingRequest(token: token, devicePublicKey: key.publicKey.x963Representation, deviceName: name, apiVersions: apiVersions)
    }

    /// As a device that isn't signed in, which is every device that pairs.
    func sendPairing(_ request: PairingRequest) async throws -> APIAnswer {
        let body = try JSONEncoder().encode(request)
        return try await application.test(.router) { client in
            try await client.execute(uri: HiveEndpoint.pairing, method: .post, body: ByteBuffer(bytes: body)) {
                APIAnswer(status: $0.status, body: Data($0.body.readableBytesView))
            }
        }
    }
}

struct CodePairingTests {
    private let fixture: APIFixture
    private let stranger = ClientAddress(key: "203.0.113.9")
    private let elsewhere = ClientAddress(key: "198.51.100.4")

    init() throws {
        fixture = try APIFixture()
        try fixture.setAddressOptions()
    }

    @Test("A device pairs through the code without signing in, gets what it needs to sign in, and can sign in")
    func pairs() async throws {
        // Arrange
        let window = try await fixture.openPairingWindow()
        let key = P256.Signing.PrivateKey()

        // Act
        let answer = try await fixture.sendPairing(fixture.pairingRequest(code: window.code, key: key))

        // Assert
        #expect(answer.status == .ok)
        let result = try answer.decoded(as: PairingResult.self)
        #expect(result.hiveID == fixture.signIn.hiveID)
        #expect(result.hiveName == "Test Hive")
        #expect(result.addresses == HiveAddresses(port: APIFixture.defaultPort, options: [
            HiveAddress(host: "studio.tail0000.ts.net", port: APIFixture.defaultPort),
            HiveAddress(host: "hive.example.com", port: 44830),
        ]))
        let device = try #require(try fixture.signIn.devices.device(id: result.deviceID))
        #expect(device.name == "Everyday Mac")
        #expect(try fixture.token(for: device, key: key).isEmpty == false)
    }

    @Test("The code carries the Hive ID, the key pin, the address options and a token")
    func codeContents() async throws {
        // Act
        let window = try await fixture.openPairingWindow()

        // Assert
        let code = try #require(PairingCode(text: window.code))
        #expect(code.hiveID == fixture.signIn.hiveID)
        #expect(code.pin == fixture.pin)
        #expect(code.addresses.map(\.host) == ["studio.tail0000.ts.net", "hive.example.com"])
        #expect(code.addresses.map(\.port) == [APIFixture.defaultPort, 44830])
        #expect(code.token.count == PairingCode.tokenLength)
        #expect(window.expiresInSeconds == Int(PairingWindowStore.lifetime))
    }

    @Test("A token works once")
    func tokenWorksOnce() async throws {
        // Arrange
        let window = try await fixture.openPairingWindow()
        _ = try await fixture.sendPairing(fixture.pairingRequest(code: window.code))

        // Act
        let again = try await fixture.sendPairing(fixture.pairingRequest(code: window.code, name: "Someone Else"))

        // Assert
        #expect(again.status == .notFound)
        #expect(try Set(fixture.signIn.devices.all().map(\.name)) == ["Test Mac", "Everyday Mac"])
    }

    @Test("A token never works after its window expires")
    func expiredTokenRefused() async throws {
        // Arrange
        let window = try await fixture.openPairingWindow()
        fixture.signIn.clock.advance(by: PairingWindowStore.lifetime)

        // Act
        let answer = try await fixture.sendPairing(fixture.pairingRequest(code: window.code))

        // Assert
        #expect(answer.status == .notFound)
        #expect(try fixture.signIn.devices.all().count == 1)
        #expect(fixture.api.pairingWindow.state() == .closed)
    }

    @Test("A token never works once its window is closed, and closing is recorded")
    func closedWindowRefused() async throws {
        // Arrange
        let window = try await fixture.openPairingWindow()
        let closed = try await fixture.send(.delete, HiveEndpoint.pairingWindow)

        // Act
        let answer = try await fixture.sendPairing(fixture.pairingRequest(code: window.code))

        // Assert
        #expect(closed.status == .noContent)
        #expect(answer.status == .notFound)
        #expect(try fixture.auditEvents().prefix(2) == [.pairingWindowClosed, .pairingWindowOpened])
    }

    @Test("No token works while no window has been opened")
    func noWindowRefused() async throws {
        // Arrange
        let code = PairingCode(
            hiveID: fixture.signIn.hiveID,
            pin: fixture.pin,
            token: Data(repeating: 7, count: PairingCode.tokenLength),
            addresses: [HiveAddress(host: "hive.example.com", port: 4483)]
        )

        // Act
        let answer = try await fixture.sendPairing(fixture.pairingRequest(code: code.text))

        // Assert
        #expect(answer.status == .notFound)
        #expect(answer.body.isEmpty)
    }

    @Test("Opening a new window closes the one before, so its token stops working")
    func newWindowReplacesOld() async throws {
        // Arrange
        let first = try await fixture.openPairingWindow()
        let second = try await fixture.openPairingWindow()

        // Act
        let withFirst = try await fixture.sendPairing(fixture.pairingRequest(code: first.code))
        let withSecond = try await fixture.sendPairing(fixture.pairingRequest(code: second.code))

        // Assert
        #expect(withFirst.status == .notFound)
        #expect(withSecond.status == .ok)
    }

    @Test("Opening a window without confirmation is refused, and opens nothing")
    func openingNeedsConfirmation() async throws {
        // Act
        let answer = try await fixture.send(.post, HiveEndpoint.pairingWindow)

        // Assert
        #expect(answer.status == .preconditionRequired)
        #expect(try answer.confirmationReasons == [.pairingWindowOpened])
        #expect(fixture.api.pairingWindow.state() == .closed)
        #expect(try fixture.auditEvents() == [.pairedOnHiveMac])
    }

    @Test("A window can't be opened without an address option, since the new device would have nowhere to go")
    func needsAddressOptions() async throws {
        // Arrange
        try fixture.setAddressOptions([])

        // Act
        let answer = try await fixture.sendConfirmed(.post, HiveEndpoint.pairingWindow)

        // Assert
        #expect(answer.status == .unprocessableContent)
        #expect(try answer.decoded(as: PairingWindowRefusal.self).problem == .noAddressOptions)
        #expect(fixture.api.pairingWindow.state() == .closed)
    }

    @Test("A window can't be opened, and a code can't be used, while Hive restarts for a new identity")
    func refusedWhileRestarting() async throws {
        // Arrange
        let window = try await fixture.openPairingWindow()
        fixture.restart.request()

        // Act
        let opening = try await fixture.sendConfirmed(.post, HiveEndpoint.pairingWindow)
        let pairing = try await fixture.sendPairing(fixture.pairingRequest(code: window.code))

        // Assert
        #expect(opening.status == .serviceUnavailable)
        #expect(pairing.status == .notFound)
        #expect(try fixture.signIn.devices.all().count == 1)
    }

    @Test("Pairing records the new device and the device that opened the window, and shows who paired")
    func pairingAudited() async throws {
        // Arrange
        let window = try await fixture.openPairingWindow()

        // Act
        let result = try await fixture.sendPairing(fixture.pairingRequest(code: window.code)).decoded(as: PairingResult.self)

        // Assert
        let entries = try fixture.auditLog.page(before: nil, limit: 2).entries
        #expect(entries.map(\.event) == [
            .pairedWithCode(openedBy: fixture.signIn.device.id, openedByName: "Test Mac"),
            .pairingWindowOpened,
        ])
        #expect(entries.first?.deviceID == result.deviceID)
        #expect(entries.first?.deviceName == "Everyday Mac")
        #expect(fixture.api.pairingWindow.state() == .used(id: window.id, deviceID: result.deviceID, deviceName: "Everyday Mac"))
    }

    @Test("A bad key or name is turned down without using up the token")
    func invalidRequestKeepsWindow() async throws {
        // Arrange
        let window = try await fixture.openPairingWindow()
        let good = try fixture.pairingRequest(code: window.code)
        let badKey = PairingRequest(token: good.token, devicePublicKey: Data([4, 1, 2]), deviceName: "Mac", apiVersions: .thisBuild)
        let badName = try fixture.pairingRequest(code: window.code, name: " ")

        // Act
        let withBadKey = try await fixture.sendPairing(badKey)
        let withBadName = try await fixture.sendPairing(badName)
        let afterwards = try await fixture.sendPairing(good)

        // Assert
        #expect(withBadKey.status == .unprocessableContent)
        #expect(withBadName.status == .unprocessableContent)
        #expect(afterwards.status == .ok)
    }

    @Test("A device on an API version Hive can't work with is told which app to update, and the token is kept")
    func incompatibleVersion() async throws {
        // Arrange
        let window = try await fixture.openPairingWindow()
        let old = try fixture.pairingRequest(code: window.code, apiVersions: APIVersions(current: 1, oldestCompatible: 1))

        // Act
        let answer = try await fixture.sendPairing(old)

        // Assert
        #expect(answer.status == .conflict)
        #expect(try answer.decoded(as: APIVersionMismatch.self).update == .beekeeper)
        #expect(fixture.api.pairingWindow.state() != .closed)
    }

    @Test("Repeated wrong tokens lock out that address, even once it has the right one, and not other addresses")
    func wrongTokensLockOut() async throws {
        // Arrange
        let window = try await fixture.openPairingWindow()
        let wrong = PairingRequest(
            token: Data(repeating: 1, count: PairingCode.tokenLength),
            devicePublicKey: P256.Signing.PrivateKey().publicKey.x963Representation,
            deviceName: "Guess",
            apiVersions: .thisBuild
        )
        for _ in 0 ..< FailedAttemptPolicy.pairing.maximumFailures {
            #expect(fixture.api.codePairing.pair(wrong, from: stranger) == .refused(.wrongToken))
        }

        // Act
        let fromStranger = fixture.api.codePairing.pair(try fixture.pairingRequest(code: window.code), from: stranger)
        let fromElsewhere = fixture.api.codePairing.pair(try fixture.pairingRequest(code: window.code), from: elsewhere)

        // Assert
        #expect(fromStranger == .lockedOut)
        guard case .paired = fromElsewhere else {
            Issue.record("Another address was locked out too: \(fromElsewhere)")
            return
        }
    }

    @Test("Requests while no window is open count towards the lockout, and the lockout ends")
    func lockoutEnds() async throws {
        // Arrange
        let request = try fixture.pairingRequest(code: PairingCode(
            hiveID: fixture.signIn.hiveID,
            pin: fixture.pin,
            token: Data(count: PairingCode.tokenLength),
            addresses: [HiveAddress(host: "hive.example.com", port: 4483)]
        ).text)
        for _ in 0 ..< FailedAttemptPolicy.pairing.maximumFailures {
            _ = fixture.api.codePairing.pair(request, from: stranger)
        }
        let lockedOut = fixture.api.codePairing.pair(request, from: stranger)
        fixture.signIn.clock.advance(by: FailedAttemptPolicy.pairing.lockout)
        let window = try await fixture.openPairingWindow()

        // Act
        let afterwards = fixture.api.codePairing.pair(try fixture.pairingRequest(code: window.code), from: stranger)

        // Assert
        #expect(lockedOut == .lockedOut)
        guard case .paired = afterwards else {
            Issue.record("The lockout didn't end: \(afterwards)")
            return
        }
    }

    @Test("A locked-out address is answered with 429")
    func lockoutAnswer() async throws {
        // Arrange
        for _ in 0 ..< FailedAttemptPolicy.pairing.maximumFailures {
            _ = fixture.api.codePairing.pair(nil, from: ClientAddress(nil))
        }

        // Act
        let answer = try await fixture.application.test(.router) { client in
            try await client.execute(uri: HiveEndpoint.pairing, method: .post, body: ByteBuffer(string: "{}")) { $0.status }
        }

        // Assert
        #expect(answer == .tooManyRequests)
    }
}
