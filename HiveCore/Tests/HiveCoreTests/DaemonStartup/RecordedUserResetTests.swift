import Darwin
import Foundation
@testable import HiveCore
import Testing

struct RecordedUserResetTests {
    private let temporary: TemporaryDirectory
    private let recordedUsers: RecordedUserStore

    init() throws {
        temporary = try TemporaryDirectory()
        recordedUsers = RecordedUserStore(directory: temporary.url.appending(path: "Hive", directoryHint: .isDirectory), owner: getuid())
        try recordedUsers.write(RecordedUser(userID: 501))
    }

    @Test("Clears the recorded user when run as root")
    func clears() throws {
        // Act
        try RecordedUserReset(process: FakeProcessIdentity(userID: 0), recordedUsers: recordedUsers).run()

        // Assert
        #expect(try recordedUsers.read() == nil)
    }

    @Test("Refuses without root, keeping the recorded user")
    func refusesWithoutRoot() throws {
        // Act / Assert
        #expect(throws: RecordedUserResetError.needsRoot) {
            try RecordedUserReset(process: FakeProcessIdentity(userID: 501), recordedUsers: recordedUsers).run()
        }
        #expect(try recordedUsers.read() == RecordedUser(userID: 501))
    }
}
