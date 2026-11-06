import HiveKit
import Testing

struct APIVersionsTests {
    @Test("The same versions work together")
    func sameVersionsWork() {
        // Act
        let outdated = APIVersions.outdatedApp(hive: .thisBuild, beekeeper: .thisBuild)

        // Assert
        #expect(outdated == nil)
    }

    @Test("A newer Hive that still understands an older Beekeeper works with it")
    func overlappingVersionsWork() {
        // Arrange
        let hive = APIVersions(current: 3, oldestCompatible: 2)
        let beekeeper = APIVersions(current: 2, oldestCompatible: 1)

        // Act
        let outdated = APIVersions.outdatedApp(hive: hive, beekeeper: beekeeper)

        // Assert
        #expect(outdated == nil)
    }

    @Test("A Beekeeper older than Hive understands is the one to update")
    func oldBeekeeperIsOutdated() {
        // Arrange
        let hive = APIVersions(current: 3, oldestCompatible: 3)
        let beekeeper = APIVersions(current: 2, oldestCompatible: 1)

        // Act
        let outdated = APIVersions.outdatedApp(hive: hive, beekeeper: beekeeper)

        // Assert
        #expect(outdated == .beekeeper)
    }

    @Test("A Hive older than Beekeeper understands is the one to update")
    func oldHiveIsOutdated() {
        // Arrange
        let hive = APIVersions(current: 1, oldestCompatible: 1)
        let beekeeper = APIVersions(current: 3, oldestCompatible: 2)

        // Act
        let outdated = APIVersions.outdatedApp(hive: hive, beekeeper: beekeeper)

        // Assert
        #expect(outdated == .hive)
    }
}
