@testable import ScoutCore
import ScoutProtocol
import Testing

struct ServerFactsReaderTests {
    @Test(
        "Each distribution is named as its os-release file names itself",
        arguments: [
            (CapturedServer.debian12, "Debian GNU/Linux 12 (bookworm)"),
            (.ubuntu2404, "Ubuntu 24.04.5 LTS"),
            (.alpine322, "Alpine Linux v3.22"),
            (.rocky9, "Rocky Linux 9.8 (Blue Onyx)"),
        ]
    )
    func distribution(server: CapturedServer, expected: String) {
        // Arrange
        let reader = ServerFactsReader(files: server.files)

        // Act
        let facts = reader.read(processesHidden: false)

        // Assert
        #expect(facts.distribution == expected)
        #expect(facts.kernel == "7.2.12-orbstack-00394-gbecdd6130068")
        #expect(facts.uptimeSeconds ?? 0 > 100_000)
        #expect(facts.scoutVersion == ScoutRelease.version.description)
    }

    @Test("A server without its files still gives a sample, with those figures left out")
    func missingFiles() {
        // Arrange
        let reader = ServerFactsReader(files: SystemFiles(root: "/nonexistent-scout-test-root"))

        // Act
        let facts = reader.read(processesHidden: false)

        // Assert
        #expect(facts.uptimeSeconds == nil)
        #expect(facts.distribution == nil)
        #expect(facts.kernel == nil)
    }

    @Test("Uptime is the first of the file's two figures")
    func uptime() {
        #expect(ServerFactsReader.uptime(parsing: "350735.47 234388.90\n") == 350_735.47)
        #expect(ServerFactsReader.uptime(parsing: "") == nil)
        #expect(ServerFactsReader.uptime(parsing: "soon") == nil)
    }
}
