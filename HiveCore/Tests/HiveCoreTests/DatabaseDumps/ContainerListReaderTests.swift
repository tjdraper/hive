import Foundation
@testable import HiveCore
import Testing

struct ContainerListReaderTests {
    private func match(_ name: String, in lines: [String]) -> ContainerMatch {
        ContainerListReader.match(serviceName: name, in: Data(lines.map { $0 + "\n" }.joined().utf8))
    }

    @Test("A Swarm service name or a Compose service name finds its one container")
    func found() {
        // Arrange
        let lines = [
            containerLine(id: "a", swarmService: "buzzingpixel_db"),
            containerLine(id: "b", composeService: "postgres"),
            containerLine(id: "c"),
        ]

        // Act & Assert
        #expect(match("buzzingpixel_db", in: lines) == .found(id: String(repeating: "a", count: 64)))
        #expect(match("postgres", in: lines) == .found(id: String(repeating: "b", count: 64)))
    }

    @Test("No match for a service name fails, including names that only contain it or are contained in it")
    func notFound() {
        // Arrange
        let lines = [
            containerLine(id: "a", swarmService: "site_db_old"),
            containerLine(id: "b", swarmService: "othersite_db"),
            containerLine(id: "c", composeService: "db"),
        ]

        // Act & Assert
        #expect(match("site_db", in: lines) == .notFound)
        #expect(match("site_db", in: []) == .notFound)
    }

    @Test("More than one match for a service name fails")
    func notUnique() {
        // Arrange
        let lines = [
            containerLine(id: "a", swarmService: "site_db"),
            containerLine(id: "b", swarmService: "site_db"),
        ]

        // Act & Assert
        #expect(match("site_db", in: lines) == .notUnique)
    }

    @Test("Lines that aren't a full container ID and two names are ignored")
    func malformedLines() {
        // Arrange
        let lines = [
            "abc123\tsite_db\t",
            String(repeating: "A", count: 64) + "\tsite_db\t",
            containerLine(id: "a", swarmService: "site_db") + "\textra",
            "",
        ]

        // Act & Assert
        #expect(match("site_db", in: lines) == .notFound)
    }
}
