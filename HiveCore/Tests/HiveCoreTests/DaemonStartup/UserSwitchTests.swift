import Darwin
import Foundation
@testable import HiveCore
import Testing

struct UserSwitchTests {
    private let account = UserAccount(
        userID: 501,
        groupID: 20,
        name: "person",
        homeDirectory: URL(filePath: "/Users/person", directoryHint: .isDirectory)
    )

    @Test("Becomes the account, setting groups before giving up root")
    func becomesAccount() throws {
        // Arrange
        let process = FakeProcessIdentity()

        // Act
        try UserSwitch(process: process).become(account)

        // Assert
        #expect(process.calls.prefix(3) == ["initgroups", "setgid", "setuid(501)"])
        #expect(process.userID == 501)
        #expect(process.effectiveUserID == 501)
        #expect(process.groupID == 20)
        #expect(process.effectiveGroupID == 20)
        #expect(process.environment == ["HOME": "/Users/person", "USER": "person", "LOGNAME": "person"])
    }

    @Test("Confirms that root can't be regained")
    func triesRegainingRoot() throws {
        // Arrange
        let process = FakeProcessIdentity()

        // Act
        try UserSwitch(process: process).become(account)

        // Assert
        #expect(process.calls.contains("setuid(0)"))
        #expect(process.calls.contains("seteuid(0)"))
    }

    @Test("Refuses to continue when root can be regained")
    func refusesRegainableRoot() {
        // Arrange
        let process = FakeProcessIdentity()
        process.rootRegainable = true

        // Act / Assert
        #expect(throws: UserSwitchError.rootStillAvailable) {
            try UserSwitch(process: process).become(account)
        }
        #expect(process.environment.isEmpty)
    }

    @Test("Refuses to continue when the user ID didn't change")
    func refusesUnchangedIdentity() {
        // Arrange
        let process = FakeProcessIdentity()
        process.ignoresUserChange = true

        // Act / Assert
        #expect(throws: UserSwitchError.identityUnchanged) {
            try UserSwitch(process: process).become(account)
        }
    }

    @Test("Stops when setting the groups fails, before changing user")
    func stopsWhenGroupsFail() {
        // Arrange
        let process = FakeProcessIdentity()
        process.failingCall = "initgroups"

        // Act / Assert
        #expect(throws: UserSwitchError.couldNotSetGroups(errno: EPERM)) {
            try UserSwitch(process: process).become(account)
        }
        #expect(process.calls == ["initgroups"])
        #expect(process.isRoot)
    }

    @Test("Stops when setting the user fails")
    func stopsWhenUserFails() {
        // Arrange
        let process = FakeProcessIdentity()
        process.failingCall = "setuid"

        // Act / Assert
        #expect(throws: UserSwitchError.couldNotSetUserID(errno: EPERM)) {
            try UserSwitch(process: process).become(account)
        }
        #expect(process.environment.isEmpty)
    }
}
