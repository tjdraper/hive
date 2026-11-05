import Darwin
import Foundation
@testable import HiveCore
import Testing

/// The data folder has to be owned by the account the daemon becomes, so the fake account is the one running the tests.
@Suite(.enabled(if: getuid() >= DaemonStartupWorkflow.firstPersonUserID, "Needs to run as a person's account"))
struct DaemonStartupWorkflowTests {
    private let temporary: TemporaryDirectory
    private let recordedUsers: RecordedUserStore
    private let person: UserAccount
    private let bundle: URL

    init() throws {
        temporary = try TemporaryDirectory()
        recordedUsers = RecordedUserStore(directory: temporary.url.appending(path: "System", directoryHint: .isDirectory), owner: getuid())
        person = UserAccount(
            userID: getuid(),
            groupID: getgid(),
            name: "person",
            homeDirectory: temporary.url.appending(path: "Home", directoryHint: .isDirectory)
        )
        bundle = try makeBundle(in: temporary)
    }

    private func workflow(
        mode: DaemonLaunchMode = .systemDaemon,
        process: FakeProcessIdentity,
        consoleUserID: uid_t?,
        tryOpening: @escaping (String) -> Int32 = { _ in 0 }
    ) -> DaemonStartupWorkflow {
        DaemonStartupWorkflow(
            mode: mode,
            process: process,
            installedBundle: InstalledBundleCheck(bundle: bundle, owner: getuid()),
            recordedUsers: recordedUsers,
            consoleUsers: FakeConsoleUser(userID: consoleUserID),
            accounts: FakeAccounts(accounts: [person]),
            dataDirectories: DataDirectoryBuilder(),
            fullDiskAccessProbe: FullDiskAccessProbe(tryOpening: tryOpening)
        )
    }

    private var dataDirectoryPath: String {
        temporary.path("Home/Library/Application Support/Hive")
    }

    @Test("On its first start, records the user logged in at the screen and becomes them")
    func firstStart() throws {
        // Arrange
        let process = FakeProcessIdentity()

        // Act
        let started = try workflow(process: process, consoleUserID: person.userID).run()

        // Assert
        #expect(try recordedUsers.read() == RecordedUser(userID: person.userID))
        #expect(process.effectiveUserID == person.userID)
        #expect(started.account == person)
        #expect(started.dataDirectory.path(percentEncoded: false) == dataDirectoryPath + "/")
        #expect(try permissions(of: dataDirectoryPath) == 0o700)
        #expect(started.fullDiskAccess == .granted)
    }

    @Test("Later starts use the recorded user, with nobody logged in")
    func laterStart() throws {
        // Arrange
        try recordedUsers.write(RecordedUser(userID: person.userID))
        let process = FakeProcessIdentity()

        // Act
        let started = try workflow(process: process, consoleUserID: nil).run()

        // Assert
        #expect(started.account == person)
        #expect(process.effectiveUserID == person.userID)
    }

    @Test("The recorded user wins over whoever is logged in now")
    func recordedUserWins() throws {
        // Arrange
        try recordedUsers.write(RecordedUser(userID: person.userID))
        let process = FakeProcessIdentity()

        // Act
        let started = try workflow(process: process, consoleUserID: person.userID + 1).run()

        // Assert
        #expect(started.account == person)
        #expect(try recordedUsers.read() == RecordedUser(userID: person.userID))
    }

    @Test("Checks Full Disk Access only after giving up root")
    func checksFullDiskAccessAfterRoot() throws {
        // Arrange
        let process = FakeProcessIdentity()
        var wasRootWhenChecked: Bool?

        // Act
        let started = try workflow(process: process, consoleUserID: person.userID) { _ in
            wasRootWhenChecked = process.isRoot
            return EPERM
        }.run()

        // Assert
        #expect(wasRootWhenChecked == false)
        #expect(started.fullDiskAccess == .missing)
    }

    @Test("Exits with nobody logged in and no recorded user, without recording anyone")
    func nobodyLoggedIn() throws {
        // Arrange
        let process = FakeProcessIdentity()

        // Act / Assert
        #expect(throws: DaemonStartupError.nobodyLoggedIn) {
            try workflow(process: process, consoleUserID: nil).run()
        }
        #expect(try recordedUsers.read() == nil)
        #expect(process.calls.isEmpty)
    }

    @Test("Refuses to record root or a system account", arguments: [uid_t(0), 1, 500])
    func refusesRecordingSystemAccount(userID: uid_t) throws {
        // Arrange
        let process = FakeProcessIdentity()

        // Act / Assert
        #expect(throws: DaemonStartupError.systemAccount(userID: userID)) {
            try workflow(process: process, consoleUserID: userID).run()
        }
        #expect(try recordedUsers.read() == nil)
        #expect(process.calls.isEmpty)
    }

    @Test("Refuses a recorded root or system account")
    func refusesRecordedSystemAccount() throws {
        // Arrange
        try recordedUsers.write(RecordedUser(userID: 0))
        let process = FakeProcessIdentity()

        // Act / Assert
        #expect(throws: DaemonStartupError.systemAccount(userID: 0)) {
            try workflow(process: process, consoleUserID: person.userID).run()
        }
        #expect(process.calls.isEmpty)
    }

    @Test("Refuses a recorded user file others can change, staying root and doing nothing else")
    func refusesUnprotectedRecord() throws {
        // Arrange
        try recordedUsers.write(RecordedUser(userID: person.userID))
        chmod(recordedUsers.fileURL.path(percentEncoded: false), 0o666)
        let process = FakeProcessIdentity()

        // Act / Assert
        #expect(throws: RecordedUserStoreError.notProtected) {
            try workflow(process: process, consoleUserID: person.userID).run()
        }
        #expect(process.calls.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dataDirectoryPath))
    }

    @Test("Refuses to run from a bundle others can change, before recording anyone")
    func refusesUnprotectedBundle() throws {
        // Arrange
        chmod(temporary.path("Hive.app/Contents/MacOS/HiveDaemon"), 0o777)
        let process = FakeProcessIdentity()

        // Act / Assert
        #expect(throws: InstalledBundleError.notProtected) {
            try workflow(process: process, consoleUserID: person.userID).run()
        }
        #expect(try recordedUsers.read() == nil)
        #expect(process.calls.isEmpty)
    }

    @Test("When giving up root fails, exits before the data folder or Full Disk Access")
    func stopsWhenSwitchFails() throws {
        // Arrange
        let process = FakeProcessIdentity()
        process.rootRegainable = true
        var checkedFullDiskAccess = false

        // Act / Assert
        #expect(throws: UserSwitchError.rootStillAvailable) {
            try workflow(process: process, consoleUserID: person.userID) { _ in
                checkedFullDiskAccess = true
                return 0
            }.run()
        }
        #expect(!checkedFullDiskAccess)
        #expect(!FileManager.default.fileExists(atPath: dataDirectoryPath))
    }

    @Test("Refuses to start unless launchd started it", arguments: [DaemonLaunchMode.systemDaemon, .developmentAgent])
    func refusesWithoutLaunchd(mode: DaemonLaunchMode) throws {
        // Arrange
        let process = FakeProcessIdentity(userID: mode == .systemDaemon ? 0 : person.userID)
        process.parentProcessID = 4321

        // Act / Assert
        #expect(throws: DaemonStartupError.notStartedByLaunchd) {
            try workflow(mode: mode, process: process, consoleUserID: person.userID).run()
        }
        #expect(process.calls.isEmpty)
        #expect(try recordedUsers.read() == nil)
    }

    @Test("Refuses to start as the system daemon without root")
    func refusesSystemDaemonWithoutRoot() throws {
        // Arrange
        let process = FakeProcessIdentity(userID: person.userID)

        // Act / Assert
        #expect(throws: DaemonStartupError.systemDaemonNotRoot) {
            try workflow(process: process, consoleUserID: person.userID).run()
        }
        #expect(try recordedUsers.read() == nil)
    }

    @Test("The development agent runs as the developer, in its own data folder, without switching user")
    func developmentAgent() throws {
        // Arrange
        let process = FakeProcessIdentity(userID: person.userID)

        // Act
        let started = try workflow(mode: .developmentAgent, process: process, consoleUserID: nil).run()

        // Assert
        #expect(started.account == person)
        #expect(started.dataDirectory.lastPathComponent == "Hive (Debug)")
        #expect(process.calls.isEmpty)
        #expect(try recordedUsers.read() == nil)
    }

    @Test("Refuses to run the development agent as root")
    func refusesRootDevelopmentAgent() {
        // Arrange
        let process = FakeProcessIdentity()

        // Act / Assert
        #expect(throws: DaemonStartupError.developmentAgentIsRoot) {
            try workflow(mode: .developmentAgent, process: process, consoleUserID: person.userID).run()
        }
    }
}
