import Darwin
import Foundation
@testable import HiveCore
import Testing

struct DataDirectoryBuilderTests {
    private let temporary: TemporaryDirectory
    private let account: UserAccount

    init() throws {
        temporary = try TemporaryDirectory()
        account = UserAccount(userID: getuid(), groupID: getgid(), name: "person", homeDirectory: temporary.url)
    }

    private var path: String {
        temporary.path("Library/Application Support/Hive")
    }

    @Test("Creates the folder so only its owner can use it")
    func creates() throws {
        // Act
        let directory = try DataDirectoryBuilder().prepare(named: "Hive", for: account)

        // Assert
        #expect(directory.path(percentEncoded: false) == path + "/")
        #expect(try permissions(of: path) == 0o700)
    }

    @Test("Tightens an existing folder others can read")
    func tightensExisting() throws {
        // Arrange
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        chmod(path, 0o755)

        // Act
        _ = try DataDirectoryBuilder().prepare(named: "Hive", for: account)

        // Assert
        #expect(try permissions(of: path) == 0o700)
    }

    @Test("Refuses a symbolic link in place of the folder")
    func refusesLink() throws {
        // Arrange
        try FileManager.default.createDirectory(atPath: temporary.path("Library/Application Support"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: temporary.path("elsewhere"), withIntermediateDirectories: false)
        symlink(temporary.path("elsewhere"), path)

        // Act / Assert
        #expect(throws: DataDirectoryError.notADirectory) {
            try DataDirectoryBuilder().prepare(named: "Hive", for: account)
        }
    }

    @Test("Refuses a folder owned by another account")
    func refusesOtherOwner() throws {
        // Arrange
        let otherAccount = UserAccount(userID: getuid() + 1, groupID: getgid(), name: "other", homeDirectory: temporary.url)

        // Act / Assert
        #expect(throws: DataDirectoryError.ownedByAnotherUser) {
            try DataDirectoryBuilder().prepare(named: "Hive", for: otherAccount)
        }
    }
}
