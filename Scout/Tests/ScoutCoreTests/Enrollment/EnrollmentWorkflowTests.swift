import Crypto
import Foundation
@testable import ScoutCore
import ScoutProtocol
import Testing

struct EnrollmentWorkflowTests {
    private let hive = FakeHive()
    private let folder: TemporaryServer
    private let store: EnrollmentStore

    init() throws {
        folder = try TemporaryServer()
        store = EnrollmentStore(directory: folder.root.path(percentEncoded: false))
    }

    private var workflow: EnrollmentWorkflow {
        EnrollmentWorkflow(connector: hive, store: store)
    }

    @Test("Enrolling sends a new key, saves it with the code's Hive, server, pin and addresses, and signs in with it")
    func enrolls() async throws {
        // Arrange
        let code = hive.code(hosts: ["hive.tail0000.ts.net", "hive.example.com"])

        // Act
        let enrollment = try await workflow.enroll(with: code)

        // Assert
        #expect(try store.load() == enrollment)
        #expect(enrollment.hiveID == hive.hiveID)
        #expect(enrollment.serverID == hive.serverID)
        #expect(enrollment.scoutID == hive.scoutID)
        #expect(enrollment.pin == hive.pin)
        #expect(enrollment.hiveAddresses == [
            HiveAddress(host: "hive.tail0000.ts.net", port: 4483),
            HiveAddress(host: "hive.example.com", port: 4483),
        ])
        #expect(try enrollment.signingKey().publicKey.x963Representation == hive.enrolledKeys.first)
        #expect(hive.signIns == 1)
        #expect(hive.connectedTo == ["hive.tail0000.ts.net"])
    }

    @Test("The saved file can be read and written only by the user Scout runs as")
    func fileIsPrivate() async throws {
        // Act
        _ = try await workflow.enroll(with: hive.code(hosts: ["hive"]))

        // Assert
        let path = folder.root.appending(path: EnrollmentStore.fileName).path(percentEncoded: false)
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test("An address that can't be reached, or shows another key, is passed over for the next")
    func triesAddressesInTurn() async throws {
        // Arrange
        hive.set { $0.reach = ["first": .unreachable, "second": .otherKey] }

        // Act
        let enrollment = try await workflow.enroll(with: hive.code(hosts: ["first", "second", "third"]))

        // Assert
        #expect(hive.connectedTo == ["first", "second", "third"])
        #expect(try store.load() == enrollment)
    }

    @Test("A Hive showing another key is refused, and reported over an address that couldn't be reached, with nothing sent or saved")
    func otherKeyRefused() async throws {
        // Arrange
        hive.set { $0.reach = ["first": .otherKey, "second": .unreachable] }

        // Act, Assert
        await #expect(throws: HiveConnectionError.keyNotPinned) {
            try await workflow.enroll(with: hive.code(hosts: ["first", "second"]))
        }
        #expect(hive.enrolledKeys.isEmpty)
        #expect(try store.load() == nil)
    }

    @Test("A code that's expired or used is refused, without trying the other addresses or saving anything")
    func refusedCode() async throws {
        // Arrange
        hive.set { $0.enrollmentStatus = 404 }

        // Act, Assert
        await #expect(throws: EnrollmentError.codeRefused) {
            try await workflow.enroll(with: hive.code(hosts: ["first", "second"]))
        }
        #expect(hive.connectedTo == ["first"])
        #expect(try store.load() == nil)
    }

    @Test("Hive answering for another server than the code's is refused, and nothing is saved")
    func wrongServer() async throws {
        // Arrange
        hive.set { $0.answeredServerID = UUID() }

        // Act, Assert
        await #expect(throws: EnrollmentError.wrongHive) {
            try await workflow.enroll(with: hive.code(hosts: ["hive"]))
        }
        #expect(try store.load() == nil)
    }

    @Test("Enrolling again replaces the key saved before")
    func enrollingAgainReplaces() async throws {
        // Arrange
        let first = try await workflow.enroll(with: hive.code(hosts: ["hive"]))

        // Act
        let second = try await workflow.enroll(with: hive.code(hosts: ["hive"]))

        // Assert
        #expect(try store.load() == second)
        #expect(try first.signingKey().rawRepresentation != second.signingKey().rawRepresentation)
    }

    @Test("A folder Scout can't write in is found before the code is used up")
    func unwritableFolder() async throws {
        // Arrange
        let missing = EnrollmentStore(directory: folder.root.appending(path: "missing").path(percentEncoded: false))

        // Act, Assert
        await #expect(throws: PrivateFileError.self) {
            try await EnrollmentWorkflow(connector: hive, store: missing).enroll(with: hive.code(hosts: ["hive"]))
        }
        #expect(hive.connectedTo.isEmpty)
    }
}

struct ScoutSessionKeeperTests {
    @Test("A session is used until a minute before it runs out, then Scout signs in again")
    func renewsBeforeExpiry() async throws {
        // Arrange
        let hive = FakeHive()
        let folder = try TemporaryServer()
        let store = EnrollmentStore(directory: folder.root.path(percentEncoded: false))
        let enrollment = try await EnrollmentWorkflow(connector: hive, store: store).enroll(with: hive.code(hosts: ["hive"]))
        let start = ContinuousClock.now
        let elapsed = Elapsed()
        var keeper = ScoutSessionKeeper(enrollment: enrollment) { start + elapsed.value }
        let pin = enrollment.hivePin

        // Act
        let counts = try await hive.withConnection(to: HiveAddress(host: "hive", port: 4483), pin: pin) { connection in
            var counts: [Int] = []
            _ = try await keeper.token(on: connection)
            counts.append(hive.signIns)
            elapsed.value = .seconds(900 - 61)
            _ = try await keeper.token(on: connection)
            counts.append(hive.signIns)
            elapsed.value = .seconds(900 - 60)
            _ = try await keeper.token(on: connection)
            counts.append(hive.signIns)
            return counts
        }

        // Assert: one sign-in while enrolling, then these.
        #expect(counts == [2, 2, 3])
    }
}

private final class Elapsed {
    var value: Duration = .zero
}
