import Darwin
import Foundation
@testable import HiveCore
import Testing

struct RecordedUserStoreTests {
    private let temporary: TemporaryDirectory
    private let store: RecordedUserStore

    init() throws {
        temporary = try TemporaryDirectory()
        store = RecordedUserStore(directory: temporary.url.appending(path: "Hive", directoryHint: .isDirectory), owner: getuid())
    }

    @Test("Reads nothing before a user is recorded")
    func readsNothing() throws {
        // Act
        let user = try store.read()

        // Assert
        #expect(user == nil)
    }

    @Test("Reads back the recorded user, from a file and folder only their owner can use")
    func roundTrip() throws {
        // Arrange
        try store.write(RecordedUser(userID: 501))

        // Act
        let user = try store.read()

        // Assert
        #expect(user == RecordedUser(userID: 501))
        #expect(try permissions(of: temporary.path("Hive")) == 0o700)
        #expect(try permissions(of: temporary.path("Hive/recorded-user.json")) == 0o600)
    }

    @Test("Refuses a file others can change")
    func refusesWritableFile() throws {
        // Arrange
        try store.write(RecordedUser(userID: 501))
        chmod(temporary.path("Hive/recorded-user.json"), 0o666)

        // Act / Assert
        #expect(throws: RecordedUserStoreError.notProtected) { try store.read() }
    }

    @Test("Refuses a folder others can change")
    func refusesWritableFolder() throws {
        // Arrange
        try store.write(RecordedUser(userID: 501))
        chmod(temporary.path("Hive"), 0o777)

        // Act / Assert
        #expect(throws: RecordedUserStoreError.notProtected) { try store.read() }
    }

    @Test("Refuses a file and folder owned by someone else")
    func refusesOtherOwner() throws {
        // Arrange
        try store.write(RecordedUser(userID: 501))
        let otherOwnersStore = RecordedUserStore(directory: store.directory, owner: getuid() + 1)

        // Act / Assert
        #expect(throws: RecordedUserStoreError.notProtected) { try otherOwnersStore.read() }
        #expect(throws: RecordedUserStoreError.notProtected) { try otherOwnersStore.write(RecordedUser(userID: 502)) }
    }

    @Test("Refuses a symbolic link in place of the file")
    func refusesLinkedFile() throws {
        // Arrange
        try store.write(RecordedUser(userID: 501))
        let elsewhere = temporary.path("elsewhere.json")
        try FileManager.default.moveItem(atPath: temporary.path("Hive/recorded-user.json"), toPath: elsewhere)
        symlink(elsewhere, temporary.path("Hive/recorded-user.json"))

        // Act / Assert
        #expect(throws: RecordedUserStoreError.notProtected) { try store.read() }
    }

    @Test("Refuses a symbolic link in place of the folder")
    func refusesLinkedFolder() throws {
        // Arrange
        let elsewhere = temporary.path("elsewhere")
        try FileManager.default.createDirectory(atPath: elsewhere, withIntermediateDirectories: false)
        symlink(elsewhere, temporary.path("Hive"))

        // Act / Assert
        #expect(throws: RecordedUserStoreError.notProtected) { try store.read() }
        #expect(throws: RecordedUserStoreError.notProtected) { try store.write(RecordedUser(userID: 501)) }
    }

    @Test("Refuses a file that doesn't hold a user")
    func refusesMalformedFile() throws {
        // Arrange
        try store.write(RecordedUser(userID: 501))
        try Data("501".utf8).write(to: store.fileURL)

        // Act / Assert
        #expect(throws: RecordedUserStoreError.malformed) { try store.read() }
    }

    @Test("Clearing forgets the recorded user")
    func clears() throws {
        // Arrange
        try store.write(RecordedUser(userID: 501))

        // Act
        try store.clear()

        // Assert
        #expect(try store.read() == nil)
    }

    @Test("Clearing with nothing recorded succeeds")
    func clearsNothing() throws {
        // Act / Assert
        try store.clear()
    }
}
