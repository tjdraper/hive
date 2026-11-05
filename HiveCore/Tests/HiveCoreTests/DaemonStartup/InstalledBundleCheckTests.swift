import Darwin
import Foundation
@testable import HiveCore
import Testing

struct InstalledBundleCheckTests {
    private let temporary: TemporaryDirectory
    private let bundle: URL

    init() throws {
        temporary = try TemporaryDirectory()
        bundle = try makeBundle(in: temporary)
    }

    @Test("Accepts a bundle only its owner can change")
    func acceptsProtectedBundle() throws {
        // Act / Assert
        try InstalledBundleCheck(bundle: bundle, owner: getuid()).verify()
    }

    @Test("Refuses a bundle owned by someone else")
    func refusesOtherOwner() {
        // Act / Assert
        #expect(throws: InstalledBundleError.notProtected) {
            try InstalledBundleCheck(bundle: bundle, owner: 0).verify()
        }
    }

    @Test("Refuses a bundle with a file others can change", arguments: [
        "Hive.app",
        "Hive.app/Contents/MacOS",
        "Hive.app/Contents/MacOS/HiveDaemon",
    ])
    func refusesWritableItem(path: String) {
        // Arrange
        chmod(temporary.path(path), 0o775)

        // Act / Assert
        #expect(throws: InstalledBundleError.notProtected) {
            try InstalledBundleCheck(bundle: bundle, owner: getuid()).verify()
        }
    }

    @Test("Refuses a symbolic link leading out of the bundle")
    func refusesLinkOut() throws {
        // Arrange
        try Data().write(to: temporary.url.appending(path: "outside"))
        symlink(temporary.path("outside"), temporary.path("Hive.app/Contents/Outside"))

        // Act / Assert
        #expect(throws: InstalledBundleError.linkLeavesBundle) {
            try InstalledBundleCheck(bundle: bundle, owner: getuid()).verify()
        }
    }

    @Test("Accepts a symbolic link within the bundle")
    func acceptsLinkWithin() throws {
        // Arrange
        symlink("MacOS/HiveDaemon", temporary.path("Hive.app/Contents/Current"))

        // Act / Assert
        try InstalledBundleCheck(bundle: bundle, owner: getuid()).verify()
    }
}
