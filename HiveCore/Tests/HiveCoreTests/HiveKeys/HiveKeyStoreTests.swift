import CryptoKit
import Darwin
import Foundation
@testable import HiveCore
import Testing

struct HiveKeyStoreTests {
    private let temporary: TemporaryDirectory
    private let store: HiveKeyStore

    init() throws {
        temporary = try TemporaryDirectory()
        store = HiveKeyStore(directory: temporary.url, factory: SoftwareKeyFactory(), owner: getuid())
    }

    @Test("Creates both keys on the first start, in files only their owner can use")
    func createsBothKeys() throws {
        // Act
        let keys = try store.loadOrCreate()

        // Assert
        #expect(keys.created == [.identity, .storage])
        #expect(try permissions(of: temporary.path("identity.key")) == 0o600)
        #expect(try permissions(of: temporary.path("storage.key")) == 0o600)
        #expect(!FileManager.default.fileExists(atPath: temporary.path("identity.key.partial")))
    }

    @Test("Loads the same keys on later starts")
    func reusesKeys() throws {
        // Arrange
        let first = try store.loadOrCreate()

        // Act
        let second = try store.loadOrCreate()

        // Assert
        #expect(second.created.isEmpty)
        #expect(second.identity.publicKey.rawRepresentation == first.identity.publicKey.rawRepresentation)
        #expect(second.storage.publicKey.rawRepresentation == first.storage.publicKey.rawRepresentation)
    }

    @Test("Creates only the missing key")
    func createsMissingKey() throws {
        // Arrange
        let first = try store.loadOrCreate()
        try FileManager.default.removeItem(atPath: temporary.path("identity.key"))

        // Act
        let second = try store.loadOrCreate()

        // Assert
        #expect(second.created == [.identity])
        #expect(second.storage.publicKey.rawRepresentation == first.storage.publicKey.rawRepresentation)
    }

    @Test("Never replaces a saved key that won't load", arguments: HiveKeyKind.allCases)
    func keepsUnloadableKey(kind: HiveKeyKind) throws {
        // Arrange
        _ = try store.loadOrCreate()
        let unloadable = Data("from another Mac".utf8)
        let path = temporary.path(kind.fileName)
        try FileManager.default.removeItem(atPath: path)
        FileManager.default.createFile(atPath: path, contents: unloadable, attributes: [.posixPermissions: 0o600])

        // Act / Assert
        #expect(throws: HiveKeyStoreError.couldNotLoad(kind)) { try store.loadOrCreate() }
        #expect(FileManager.default.contents(atPath: path) == unloadable)
    }

    @Test("Saves nothing when a key can't be made")
    func savesNothingWhenMakingFails() throws {
        // Arrange
        let refusingStore = HiveKeyStore(directory: temporary.url, factory: SoftwareKeyFactory(refusesToMake: true), owner: getuid())

        // Act / Assert
        #expect(throws: HiveKeyStoreError.couldNotCreate(.identity)) { try refusingStore.loadOrCreate() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporary.url.path(percentEncoded: false)).isEmpty)
    }

    @Test("Refuses a key file others can read")
    func refusesReadableFile() throws {
        // Arrange
        _ = try store.loadOrCreate()
        chmod(temporary.path("storage.key"), 0o644)

        // Act / Assert
        #expect(throws: OwnerOnlyFileError.notProtected) { try store.loadOrCreate() }
    }

    @Test("Refuses a key file owned by someone else")
    func refusesOtherOwner() throws {
        // Arrange
        _ = try store.loadOrCreate()
        let otherOwnersStore = HiveKeyStore(directory: temporary.url, factory: SoftwareKeyFactory(), owner: getuid() + 1)

        // Act / Assert
        #expect(throws: OwnerOnlyFileError.notProtected) { try otherOwnersStore.loadOrCreate() }
    }

    @Test("Refuses a symbolic link in place of a key file")
    func refusesLinkedFile() throws {
        // Arrange
        _ = try store.loadOrCreate()
        let elsewhere = temporary.path("elsewhere.key")
        try FileManager.default.moveItem(atPath: temporary.path("identity.key"), toPath: elsewhere)
        symlink(elsewhere, temporary.path("identity.key"))

        // Act / Assert
        #expect(throws: OwnerOnlyFileError.notProtected) { try store.loadOrCreate() }
    }

    @Test("Replaces a partial file left by an interrupted start")
    func replacesPartialFile() throws {
        // Arrange
        FileManager.default.createFile(atPath: temporary.path("identity.key.partial"), contents: Data("half".utf8))

        // Act
        let keys = try store.loadOrCreate()

        // Assert
        #expect(keys.created == [.identity, .storage])
        #expect(!FileManager.default.fileExists(atPath: temporary.path("identity.key.partial")))
    }
}
